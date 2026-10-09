# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.used.}

import chronos, chronos/osdefs, nativesockets, unittest2
import chronos/osutils
import lsquic/[lsquic_ffi, context/context, context/io]
import ./helpers/[address, trackers]
import std/os

when not defined(windows):
  from posix import EAGAIN, EBADF, errno

proc makeOutSpec(
    iov: ptr struct_iovec, local, dest: ptr Sockaddr_storage
): struct_lsquic_out_spec =
  struct_lsquic_out_spec(
    iov: iov,
    iovlen: 1,
    local_sa: cast[ptr SockAddr](local),
    dest_sa: cast[ptr SockAddr](dest),
  )

proc makeContext(fd: SocketHandle): QuicContext =
  var response = QuicContext(fd: cint(fd))
  when defined(windows):
    doAssert response.initPacketIo(fd)
  response

proc receiveWithTimeout(
    fd: SocketHandle,
    received: var array[3, byte],
    remoteStorage: var Sockaddr_storage,
    remoteLen: var SockLen,
): int =
  doAssert setDescriptorBlocking(fd, false).isOk()
  let buffer =
    when defined(windows):
      cast[cstring](addr received[0])
    else:
      addr received[0]

  var response: int = -1
  for _ in 0 ..< 100:
    remoteLen = sizeof(remoteStorage).SockLen
    response = recvfrom(
      fd,
      buffer,
      received.len.cint,
      0,
      cast[ptr SockAddr](addr remoteStorage),
      addr remoteLen,
    ).int
    if response >= 0:
      return response
    os.sleep(10)
  response

suite "packets out":
  teardown:
    checkTrackers()

  test "a send with no packets sent out reports -1":
    let ctx = QuicContext(fd: -1)
    var
      payload = @[1'u8, 2, 3]
      localStorage = toSockaddrStorage(initTAddress("127.0.0.1:1000"))
      destStorage = toSockaddrStorage(initTAddress("127.0.0.1:4433"))
      iov = struct_iovec(iov_base: addr payload[0], iov_len: payload.len.csize_t)
      spec = makeOutSpec(addr iov, addr localStorage, addr destStorage)

    let res = sendPacketsOut(cast[pointer](ctx), addr spec, 1)
    # The engine reads errno to decide whether to retry or close the connection.
    when not defined(windows):
      check errno == EBADF

    check res == -1

  test "a send with some packets sent out reports the count":
    # Returning -1 would make the engine resend a datagram that already went out.
    let fd = createNativeSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    defer:
      nativesockets.close(fd)

    let ctx = makeContext(fd)
    var
      payload = @[1'u8, 2, 3]
      localStorage = toSockaddrStorage(initTAddress("127.0.0.1:1000"))
      ipv4DestStorage = toSockaddrStorage(initTAddress("127.0.0.1:4433"))
      ipv6DestStorage = toSockaddrStorage(initTAddress("[::1]:4433"))
      iov = struct_iovec(iov_base: addr payload[0], iov_len: payload.len.csize_t)
      specs = [
        makeOutSpec(addr iov, addr localStorage, addr ipv4DestStorage),
        makeOutSpec(addr iov, addr localStorage, addr ipv6DestStorage),
      ]

    let res = sendPacketsOut(cast[pointer](ctx), addr specs[0], 2)
    # Linux overwrites errno with EAGAIN here, the other platforms leave alone
    # whatever the failed send set.
    when defined(linux):
      check errno == EAGAIN

    check res == 1

  test "a batch larger than one sendmmsg call sends every packet":
    # SendmmsgBatchSize is 64, so +1 specs take two sendmmsg calls.
    const SpecCount = 64 + 1 # const is not exported

    let fd = createNativeSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    defer:
      nativesockets.close(fd)

    let ctx = makeContext(fd)
    var
      payload = @[1'u8, 2, 3]
      localStorage = toSockaddrStorage(initTAddress("127.0.0.1:1000"))
      destStorage = toSockaddrStorage(initTAddress("127.0.0.1:4433"))
      iov = struct_iovec(iov_base: addr payload[0], iov_len: payload.len.csize_t)
      specs = newSeq[struct_lsquic_out_spec](SpecCount)
    for spec in specs.mitems:
      spec = makeOutSpec(addr iov, addr localStorage, addr destStorage)

    check sendPacketsOut(cast[pointer](ctx), addr specs[0], SpecCount.cuint) == SpecCount

  test "packet info selects the requested IPv4 source address":
    let
      senderFd = createNativeSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
      receiverFd = createNativeSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
      requestedSource = when defined(linux): "127.0.0.2" else: "127.0.0.1"
    defer:
      nativesockets.close(senderFd)
      nativesockets.close(receiverFd)

    var
      senderBind = toSockaddrStorage(initTAddress("0.0.0.0:0"))
      receiverBind = toSockaddrStorage(initTAddress(requestedSource & ":0"))
    require bindSocket(
      senderFd, cast[ptr SockAddr](addr senderBind), sizeof(Sockaddr_in).SockLen
    ) == 0
    require bindSocket(
      receiverFd, cast[ptr SockAddr](addr receiverBind), sizeof(Sockaddr_in).SockLen
    ) == 0

    var receiverLen = sizeof(receiverBind).SockLen
    require getsockname(
      receiverFd, cast[ptr SockAddr](addr receiverBind), addr receiverLen
    ) == 0

    let ctx = makeContext(senderFd)
    var
      payload = @[byte(1), 2, 3]
      localStorage = toSockaddrStorage(initTAddress(requestedSource & ":0"))
      iov = struct_iovec(iov_base: addr payload[0], iov_len: payload.len.csize_t)
      spec = makeOutSpec(addr iov, addr localStorage, addr receiverBind)

    require sendPacketsOut(cast[pointer](ctx), addr spec, 1) == 1

    var
      received: array[3, byte]
      remoteStorage: Sockaddr_storage
      remoteLen = sizeof(remoteStorage).SockLen
    check receiveWithTimeout(receiverFd, received, remoteStorage, remoteLen) ==
      received.len

    var remote: TransportAddress
    fromSAddr(addr remoteStorage, remoteLen, remote)
    check remote.toIpAddress() == parseIpAddress(requestedSource)

  test "packet info selects the requested IPv6 source address":
    let
      senderFd = createNativeSocket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
      receiverFd = createNativeSocket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
    defer:
      nativesockets.close(senderFd)
      nativesockets.close(receiverFd)

    var
      senderBind = toSockaddrStorage(initTAddress("[::]:0"))
      receiverBind = toSockaddrStorage(initTAddress("[::1]:0"))
    require bindSocket(
      senderFd, cast[ptr SockAddr](addr senderBind), sizeof(Sockaddr_in6).SockLen
    ) == 0
    require bindSocket(
      receiverFd, cast[ptr SockAddr](addr receiverBind), sizeof(Sockaddr_in6).SockLen
    ) == 0

    var receiverLen = sizeof(receiverBind).SockLen
    require getsockname(
      receiverFd, cast[ptr SockAddr](addr receiverBind), addr receiverLen
    ) == 0

    let ctx = makeContext(senderFd)
    var
      payload = @[byte(1), 2, 3]
      localStorage = toSockaddrStorage(initTAddress("[::1]:0"))
      iov = struct_iovec(iov_base: addr payload[0], iov_len: payload.len.csize_t)
      spec = makeOutSpec(addr iov, addr localStorage, addr receiverBind)

    require sendPacketsOut(cast[pointer](ctx), addr spec, 1) == 1

    var
      received: array[3, byte]
      remoteStorage: Sockaddr_storage
      remoteLen = sizeof(remoteStorage).SockLen
    check receiveWithTimeout(receiverFd, received, remoteStorage, remoteLen) ==
      received.len

    var remote: TransportAddress
    fromSAddr(addr remoteStorage, remoteLen, remote)
    check remote.toIpAddress() == parseIpAddress("::1")
