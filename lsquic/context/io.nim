# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH 

import chronos
import chronos/osdefs
import chronicles
import ./context
import ../lsquic_ffi
import ../helpers/transportaddr

when defined(windows):
  var callbackErrno {.importc: "errno", header: "<errno.h>".}: cint
  let
    callbackAgain {.importc: "EAGAIN", header: "<errno.h>".}: cint
    callbackMsgSize {.importc: "EMSGSIZE", header: "<errno.h>".}: cint
    callbackIoError {.importc: "EIO", header: "<errno.h>".}: cint
else:
  import posix

logScope:
  topics = "lsquic"

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
  let specsArr = cast[ptr UncheckedArray[struct_lsquic_out_spec]](specs)
  const BatchSize = 64
  var
    packets: array[BatchSize, DatagramNativeOut]
    sent = 0
  while sent < nspecs.int:
    let count = min(packets.len, nspecs.int - sent)
    for i in 0 ..< count:
      let spec = specsArr[sent + i]
      packets[i] = DatagramNativeOut(
        remote: cast[ptr Sockaddr_storage](spec.dest_sa),
        remoteLen: sockAddrLen(spec.dest_sa.sa_family.int),
        buffers: cast[ptr UncheckedArray[DatagramBuffer]](spec.iov),
        bufferCount: spec.iovlen.int,
      )
    let res = quicCtx.udp.trySendNativeBatch(packets.toOpenArray(0, count - 1))
    sent += res.sent
    if res.sent < count:
      # lsquic owns unsent payloads. A short sendmmsg has no known error;
      # preserve the existing retry convention at the C callback boundary.
      when defined(windows):
        # The engine reads C errno, not Winsock's thread-local error.
        callbackErrno =
          if res.error in [OSErrorCode(0), OSErrorCode(WSAEWOULDBLOCK)]:
            callbackAgain
          elif res.error == OSErrorCode(WSAEMSGSIZE):
            callbackMsgSize
          else:
            callbackIoError
      else:
        errno =
          if res.error == OSErrorCode(0):
            EAGAIN
          else:
            cint(res.error)
      return if sent == 0: -1 else: sent.cint
  sent.cint
