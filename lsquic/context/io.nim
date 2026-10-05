# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH 

import chronos
import chronos/osdefs
import chronicles
import ./context
import ../lsquic_ffi
import ../helpers/logging
import ../helpers/transportaddr
import std/[nativesockets, net]

when not defined(windows):
  import posix

logScope:
  topics = "lsquic"

const MaxBatch = 1024
  ## Upper bound on the stack WSABUF array in the Windows send path (`sendPacketsOut`).
  ## In practice `iovlen` is small; if it exceeds this bound, `sendPacketsOut`
  ## falls back to a heap-allocated seq.

when defined(linux):
  {.passc: "-D_GNU_SOURCE".}

  const SendmmsgBatchSize = 64

  type MMsgHdr {.importc: "struct mmsghdr", header: "<sys/socket.h>", bycopy.} = object
    msg_hdr: Tmsghdr
    msg_len: cuint

  proc sendmmsg(
    sockfd: SocketHandle, msgvec: ptr MMsgHdr, vlen: cuint, flags: cint
  ): cint {.importc, header: "<sys/socket.h>".}

when defined(windows):
  import std/winlean

  {.pragma: wsa, stdcall, dynlib: "ws2_32.dll".}

  type WSABUF* = object
    len*: culong
    buf*: ptr char

  proc WSASendTo*(
    s: SocketHandle,
    lpBuffers: ptr WSABUF,
    dwBufferCount: culong,
    lpNumberOfBytesSent: ptr culong,
    dwFlags: culong,
    lpTo: ptr SockAddr,
    iToLen: cint,
    lpOverlapped: pointer,
    lpCompletionRoutine: pointer,
  ): cint {.wsa, importc: "WSASendTo".}

proc prepareDestAddr(
    localSa: ptr SockAddr,
    destSa: ptr SockAddr,
    destStorage: var Sockaddr_storage,
    destAddrLen: var SockLen,
) =
  ## Chronos normalizes IPv4 peers on dual-stack `::` sockets back to IPv4.
  ## When lsquic later asks us to send on that IPv6 socket, sending directly to
  ## an AF_INET destination can fail with EINVAL. Re-map the destination to an
  ## IPv6-mapped address when the local path is IPv6.
  if localSa.isIPv6Family() and destSa.isIPv4Family():
    let mappedDest = destSa.toTransportAddress().toIPv6()
    mappedDest.toSAddr(destStorage, destAddrLen)
  else:
    destAddrLen = sockAddrLen(destSa.sa_family.int)
    copyMem(addr destStorage, destSa, destAddrLen)

when not defined(windows):
  proc makeMsgHdr(
      spec: struct_lsquic_out_spec,
      destStorage: var Sockaddr_storage,
      destAddrLen: SockLen,
  ): Tmsghdr =
    when defined(linux) and defined(x86_64) and not defined(android):
      Tmsghdr(
        msg_name: cast[pointer](addr destStorage),
        msg_namelen: destAddrLen,
        msg_iov: cast[ptr IOVec](spec.iov),
        msg_iovlen: spec.iovlen.csize_t,
        msg_control: nil,
        msg_controllen: 0,
        msg_flags: 0,
      )
    else:
      Tmsghdr(
        msg_name: cast[pointer](addr destStorage),
        msg_namelen: destAddrLen,
        msg_iov: cast[ptr IOVec](spec.iov),
        msg_iovlen: spec.iovlen.cint,
        msg_control: nil,
        msg_controllen: 0,
        msg_flags: 0,
      )

proc packetIn*(
    ctx: QuicContext,
    data: openArray[byte],
    local: TransportAddress,
    remote: TransportAddress,
    ecn: cint = 0,
): bool =
  ## Returns false when the datagram was not handed to the engine or the engine
  ## reports an error while accepting it.
  if data.len == 0 or not ctx.isRunning():
    return false

  var
    localAddress: Sockaddr_storage
    localAddrLen: SockLen
    remoteAddress: Sockaddr_storage
    remoteAddrLen: SockLen

  local.toSAddr(localAddress, localAddrLen)
  remote.toSAddr(remoteAddress, remoteAddrLen)

  let status = lsquic_engine_packet_in(
    ctx.engine,
    cast[ptr uint8](addr data[0]),
    data.len.csize_t,
    cast[ptr SockAddr](addr localAddress),
    cast[ptr SockAddr](addr remoteAddress),
    cast[pointer](ctx),
    ecn,
  )

  if status < 0:
    trace "Failed to process UDP datagram", bytes = data.len, local, remote
    return false

  true

proc sendPacketsOut*(
    ctx: pointer, specs: ptr struct_lsquic_out_spec, nspecs: cuint
): cint {.cdecl.} =
  let quicCtx = cast[QuicContext](ctx)
  if nspecs == 0:
    return 0

  let specsArr = cast[ptr UncheckedArray[struct_lsquic_out_spec]](specs)

  when defined(linux):
    var
      destStorages {.noinit.}: array[SendmmsgBatchSize, Sockaddr_storage]
      msgs {.noinit.}: array[SendmmsgBatchSize, MMsgHdr]
      sent = 0

    while sent < nspecs.int:
      let nmsgs = min(nspecs.int - sent, SendmmsgBatchSize)
      for i in 0 ..< nmsgs:
        let curr = specsArr[sent + i]
        var destAddrLen: SockLen
        prepareDestAddr(curr.local_sa, curr.dest_sa, destStorages[i], destAddrLen)
        msgs[i] =
          MMsgHdr(msg_hdr: makeMsgHdr(curr, destStorages[i], destAddrLen), msg_len: 0)

      let res = sendmmsg(SocketHandle(quicCtx.fd), addr msgs[0], nmsgs.cuint, 0)
      if res < 0:
        let savedErrno = errno
        trace "Failed to send UDP datagram batch",
          sent, nspecs, error = osErrorLabel(savedErrno)
        errno = savedErrno
        if sent == 0:
          return -1
        return sent.cint

      sent += res.int
      if res < nmsgs.cint:
        trace "Sent only part of UDP datagram batch",
          sent, nspecs, error = osErrorLabel(EAGAIN)
        errno = EAGAIN
        return sent.cint

    sent.cint
  else:
    when defined(windows):
      var
        bufs {.noinit.}: array[MaxBatch, WSABUF]
        overflow: seq[WSABUF]
    var sent = 0
    for i in 0 ..< nspecs.int:
      let curr = specsArr[i]
      var
        destStorage: Sockaddr_storage
        destAddrLen: SockLen
      prepareDestAddr(curr.local_sa, curr.dest_sa, destStorage, destAddrLen)

      when defined(windows):
        let
          iovArr = cast[ptr UncheckedArray[struct_iovec]](curr.iov)
          iovlen = curr.iovlen.int
          dst =
            if iovlen <= bufs.len:
              cast[ptr UncheckedArray[WSABUF]](addr bufs[0])
            else:
              overflow.setLen(iovlen)
              cast[ptr UncheckedArray[WSABUF]](addr overflow[0])

        for j in 0 ..< iovlen:
          let src = iovArr[j]
          dst[j].len = culong(src.iov_len)
          dst[j].buf = cast[ptr char](src.iov_base)

        var bytesSent: culong = 0
        let res = WSASendTo(
          SocketHandle(quicCtx.fd),
          addr dst[0],
          culong(iovlen),
          addr bytesSent,
          0, # flags
          cast[ptr SockAddr](addr destStorage),
          cint(destAddrLen),
          nil,
          nil, # no overlapped
        )
        if res != 0:
          let errorCode = osdefs.wsaGetLastError()
          trace "Failed to send UDP datagram",
            sent, nspecs, error = osErrorLabel(errorCode)
          if sent == 0:
            return -1
          break
      else:
        let msg = makeMsgHdr(curr, destStorage, destAddrLen)

        let res = sendmsg(SocketHandle(quicCtx.fd), msg.addr, 0)
        if res < 0:
          let savedErrno = errno
          trace "Failed to send UDP datagram",
            sent, nspecs, error = osErrorLabel(savedErrno)
          errno = savedErrno
          if sent == 0:
            return -1
          break

      sent.inc

    sent.cint

when defined(lsquic_testing):
  proc prepareDestAddrForTest*(
      localSa: ptr SockAddr,
      destSa: ptr SockAddr,
      destStorage: var Sockaddr_storage,
      destAddrLen: var SockLen,
  ) =
    ## Test-only accessor for the destination remapping.
    prepareDestAddr(localSa, destSa, destStorage, destAddrLen)
