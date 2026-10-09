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

type ControlBuffer {.union.} = object
  alignment: uint
  data: array[128, byte]

when defined(windows):
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

when defined(linux) or defined(macosx):
  when defined(macosx):
    {.passc: "-D__APPLE_USE_RFC_3542".}

  type
    InPktInfo {.importc: "struct in_pktinfo", header: "<netinet/in.h>", bycopy.} = object
      ipi_ifindex: cint
      ipi_spec_dst: InAddr
      ipi_addr: InAddr

    In6PktInfo {.importc: "struct in6_pktinfo", header: "<netinet/in.h>", bycopy.} = object
      ipi6_addr: In6Addr
      ipi6_ifindex: cuint

  var
    IP_PKTINFO {.importc, header: "<netinet/in.h>".}: cint
    IPV6_PKTINFO {.importc, header: "<netinet/in.h>".}: cint

  when defined(macosx):
    var IP_RECVDSTADDR {.importc, header: "<netinet/in.h>".}: cint

when not defined(windows):
  proc prepareSourceAddr(
      localSa: ptr SockAddr, control: var ControlBuffer, msg: var Tmsghdr
  ) =
    when defined(linux) or defined(macosx):
      var local = localSa.toTransportAddress()
      if local.isV4Mapped():
        local = local.toIPv4()
      if local.isAnyLocal():
        return

      zeroMem(addr control.data[0], control.data.len)
      msg.msg_control = addr control.data[0]

      let cmsg = cast[ptr Tcmsghdr](msg.msg_control)
      if local.family == AddressFamily.IPv4:
        msg.msg_controllen =
          typeof(msg.msg_controllen)(CMSG_SPACE(sizeof(InPktInfo).csize_t))
        cmsg.cmsg_len = typeof(cmsg.cmsg_len)(CMSG_LEN(sizeof(InPktInfo).csize_t))
        cmsg.cmsg_level = IPPROTO_IP
        cmsg.cmsg_type = IP_PKTINFO
        let info = cast[ptr InPktInfo](CMSG_DATA(cmsg))
        copyMem(
          addr info.ipi_spec_dst, unsafeAddr local.address_v4[0], local.address_v4.len
        )
      elif local.family == AddressFamily.IPv6:
        msg.msg_controllen =
          typeof(msg.msg_controllen)(CMSG_SPACE(sizeof(In6PktInfo).csize_t))
        cmsg.cmsg_len = typeof(cmsg.cmsg_len)(CMSG_LEN(sizeof(In6PktInfo).csize_t))
        cmsg.cmsg_level = IPPROTO_IPV6
        cmsg.cmsg_type = IPV6_PKTINFO
        let info = cast[ptr In6PktInfo](CMSG_DATA(cmsg))
        copyMem(
          addr info.ipi6_addr, unsafeAddr local.address_v6[0], local.address_v6.len
        )

when defined(linux) or defined(macosx):
  proc recvPacket*(
      fd: SocketHandle,
      buf: var seq[byte],
      boundLocal: TransportAddress,
      local, remote: var TransportAddress,
  ): int {.raises: [].} =
    var
      remoteStorage: Sockaddr_storage
      iov = IOVec(iov_base: addr buf[0], iov_len: buf.len.csize_t)
      control: ControlBuffer
      msg = Tmsghdr(
        msg_name: addr remoteStorage,
        msg_namelen: SockLen(sizeof(remoteStorage)),
        msg_iov: addr iov,
        msg_iovlen: 1,
        msg_control: addr control.data[0],
      )
    msg.msg_controllen = typeof(msg.msg_controllen)(control.data.len)

    let response = recvmsg(fd, addr msg, 0)
    if response < 0:
      return response
    if (msg.msg_flags and MSG_CTRUNC) != 0:
      trace "Dropping UDP datagram with truncated packet info", boundLocal
      return -1

    remote = toTransportAddress(cast[ptr SockAddr](addr remoteStorage))
    if boundLocal.family == AddressFamily.IPv6 and remote.isV4Mapped():
      remote = remote.toIPv4()
    local = boundLocal

    var cmsg = CMSG_FIRSTHDR(addr msg)
    while not cmsg.isNil:
      when defined(linux):
        if cmsg.cmsg_level == IPPROTO_IP and cmsg.cmsg_type == IP_PKTINFO:
          let info = cast[ptr InPktInfo](CMSG_DATA(cmsg))
          local = TransportAddress(family: AddressFamily.IPv4, port: boundLocal.port)
          copyMem(addr local.address_v4[0], addr info.ipi_addr, local.address_v4.len)
          break
      else:
        if cmsg.cmsg_level == IPPROTO_IP and cmsg.cmsg_type == IP_RECVDSTADDR:
          local = TransportAddress(family: AddressFamily.IPv4, port: boundLocal.port)
          copyMem(addr local.address_v4[0], CMSG_DATA(cmsg), local.address_v4.len)
          break
      if cmsg.cmsg_level == IPPROTO_IPV6 and cmsg.cmsg_type == IPV6_PKTINFO:
        let info = cast[ptr In6PktInfo](CMSG_DATA(cmsg))
        local = TransportAddress(family: AddressFamily.IPv6, port: boundLocal.port)
        copyMem(addr local.address_v6[0], addr info.ipi6_addr, local.address_v6.len)
        break
      cmsg = CMSG_NXTHDR(addr msg, cmsg)

    local = local.matchSocketFamily(boundLocal)
    response

when defined(windows):
  const WsaMsgCtrunc = DWORD(0x0200)

  func wsaCmsgAlign(value: uint): uint =
    (value + uint(sizeof(uint) - 1)) and not uint(sizeof(uint) - 1)

  proc prepareSourceAddr(
      localSa: ptr SockAddr, control: var ControlBuffer, msg: var osdefs.WSAMSG
  ) =
    var local = localSa.toTransportAddress()
    if local.isV4Mapped():
      local = local.toIPv4()
    if local.isAnyLocal():
      return

    zeroMem(addr control.data[0], control.data.len)
    let
      headerLen = wsaCmsgAlign(uint(sizeof(osdefs.WSACMSGHDR)))
      header = cast[ptr osdefs.WSACMSGHDR](addr control.data[0])
      data = cast[pointer](cast[uint](header) + headerLen)

    msg.control.buf = cast[cstring](addr control.data[0])
    if local.family == AddressFamily.IPv4:
      header.cmsg_len = headerLen + uint(sizeof(osdefs.WinInPktInfo))
      header.cmsg_level = osdefs.IPPROTO_IP
      header.cmsg_type = osdefs.IP_PKTINFO
      msg.control.len = ULONG(wsaCmsgAlign(header.cmsg_len))
      let info = cast[ptr osdefs.WinInPktInfo](data)
      copyMem(addr info.ipi_addr, unsafeAddr local.address_v4[0], local.address_v4.len)
    elif local.family == AddressFamily.IPv6:
      header.cmsg_len = headerLen + uint(sizeof(osdefs.WinIn6PktInfo))
      header.cmsg_level = osdefs.IPPROTO_IPV6
      header.cmsg_type = osdefs.IPV6_PKTINFO
      msg.control.len = ULONG(wsaCmsgAlign(header.cmsg_len))
      let info = cast[ptr osdefs.WinIn6PktInfo](data)
      copyMem(addr info.ipi6_addr, unsafeAddr local.address_v6[0], local.address_v6.len)

  proc recvPacket*(
      ctx: QuicContext,
      fd: SocketHandle,
      buf: var seq[byte],
      boundLocal: TransportAddress,
      local, remote: var TransportAddress,
  ): int {.raises: [].} =
    var
      remoteStorage: Sockaddr_storage
      control: ControlBuffer
      data = osdefs.WSABUF(len: ULONG(buf.len), buf: cast[cstring](addr buf[0]))
      msg = osdefs.WSAMSG(
        name: cast[ptr SockAddr](addr remoteStorage),
        namelen: cint(sizeof(remoteStorage)),
        lpBuffers: addr data,
        dwBufferCount: DWORD(1),
        control: osdefs.WSABUF(
          len: ULONG(control.data.len), buf: cast[cstring](addr control.data[0])
        ),
      )
      bytesReceived: DWORD

    if ctx.recvMsg(fd, addr msg, addr bytesReceived) != 0:
      return -1
    if (msg.dwFlags and WsaMsgCtrunc) != 0:
      trace "Dropping UDP datagram with truncated packet info", boundLocal
      return -1

    remote = toTransportAddress(cast[ptr SockAddr](addr remoteStorage))
    if boundLocal.family == AddressFamily.IPv6 and remote.isV4Mapped():
      remote = remote.toIPv4()
    local = boundLocal

    var
      cursor = cast[uint](msg.control.buf)
      finish = cursor + uint(msg.control.len)
    while cursor + uint(sizeof(osdefs.WSACMSGHDR)) <= finish:
      let header = cast[ptr osdefs.WSACMSGHDR](cursor)
      if header.cmsg_len < uint(sizeof(osdefs.WSACMSGHDR)) or
          cursor + header.cmsg_len > finish:
        break
      let data = cast[pointer](cursor + wsaCmsgAlign(uint(sizeof(osdefs.WSACMSGHDR))))
      if header.cmsg_level == osdefs.IPPROTO_IP and header.cmsg_type == osdefs.IP_PKTINFO:
        let info = cast[ptr osdefs.WinInPktInfo](data)
        local = TransportAddress(family: AddressFamily.IPv4, port: boundLocal.port)
        copyMem(addr local.address_v4[0], addr info.ipi_addr, local.address_v4.len)
        break
      if header.cmsg_level == osdefs.IPPROTO_IPV6 and
          header.cmsg_type == osdefs.IPV6_PKTINFO:
        let info = cast[ptr osdefs.WinIn6PktInfo](data)
        local = TransportAddress(family: AddressFamily.IPv6, port: boundLocal.port)
        copyMem(addr local.address_v6[0], addr info.ipi6_addr, local.address_v6.len)
        break
      cursor += wsaCmsgAlign(header.cmsg_len)

    local = local.matchSocketFamily(boundLocal)
    bytesReceived.int

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
      control: var ControlBuffer,
  ): Tmsghdr =
    var response: Tmsghdr
    when defined(linux) and defined(x86_64) and not defined(android):
      response = Tmsghdr(
        msg_name: cast[pointer](addr destStorage),
        msg_namelen: destAddrLen,
        msg_iov: cast[ptr IOVec](spec.iov),
        msg_iovlen: spec.iovlen.csize_t,
        msg_control: nil,
        msg_controllen: 0,
        msg_flags: 0,
      )
    else:
      response = Tmsghdr(
        msg_name: cast[pointer](addr destStorage),
        msg_namelen: destAddrLen,
        msg_iov: cast[ptr IOVec](spec.iov),
        msg_iovlen: spec.iovlen.cint,
        msg_control: nil,
        msg_controllen: 0,
        msg_flags: 0,
      )
    prepareSourceAddr(spec.local_sa, control, response)
    response

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
      controls {.noinit.}: array[SendmmsgBatchSize, ControlBuffer]
      msgs {.noinit.}: array[SendmmsgBatchSize, MMsgHdr]
      sent = 0

    while sent < nspecs.int:
      let nmsgs = min(nspecs.int - sent, SendmmsgBatchSize)
      for i in 0 ..< nmsgs:
        let curr = specsArr[sent + i]
        var destAddrLen: SockLen
        prepareDestAddr(curr.local_sa, curr.dest_sa, destStorages[i], destAddrLen)
        msgs[i] = MMsgHdr(
          msg_hdr: makeMsgHdr(curr, destStorages[i], destAddrLen, controls[i]),
          msg_len: 0,
        )

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
        bufs {.noinit.}: array[MaxBatch, osdefs.WSABUF]
        overflow: seq[osdefs.WSABUF]
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
              cast[ptr UncheckedArray[osdefs.WSABUF]](addr bufs[0])
            else:
              overflow.setLen(iovlen)
              cast[ptr UncheckedArray[osdefs.WSABUF]](addr overflow[0])

        for j in 0 ..< iovlen:
          let src = iovArr[j]
          dst[j].len = ULONG(src.iov_len)
          dst[j].buf = cast[cstring](src.iov_base)

        var
          control: ControlBuffer
          bytesSent: DWORD
          msg = osdefs.WSAMSG(
            name: cast[ptr SockAddr](addr destStorage),
            namelen: cint(destAddrLen),
            lpBuffers: addr dst[0],
            dwBufferCount: DWORD(iovlen),
          )
        prepareSourceAddr(curr.local_sa, control, msg)
        let res = quicCtx.sendMsg(SocketHandle(quicCtx.fd), addr msg, addr bytesSent)
        if res != 0:
          let errorCode = osdefs.wsaGetLastError()
          trace "Failed to send UDP datagram",
            sent, nspecs, error = osErrorLabel(errorCode)
          if sent == 0:
            return -1
          break
      else:
        var control: ControlBuffer
        let msg = makeMsgHdr(curr, destStorage, destAddrLen, control)

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
