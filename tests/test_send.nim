# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.used.}

import chronos, chronos/osdefs, chronos/unittest2/asynctests
import lsquic/[lsquic_ffi, context/context, context/io]
import ./helpers/[address, trackers]

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

proc ignorePacket(
    t: DatagramTransport,
    data: openArray[byte],
    remote: TransportAddress,
    error: OSErrorCode,
) {.gcsafe.} =
  discard

suite "packets out":
  teardown:
    checkTrackers()

  asyncTest "a send with no packets sent out reports -1":
    let udp = newDatagramTransportSync(ignorePacket, local = AutoAddressIP4)
    await udp.closeWait()
    let ctx = QuicContext(udp: udp)
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

  asyncTest "a send with some packets sent out reports the count":
    # Returning -1 would make the engine resend a datagram that already went out.
    let udp = newDatagramTransportSync(ignorePacket, local = AutoAddressIP4)
    defer:
      await udp.closeWait()

    let ctx = QuicContext(udp: udp)
    var
      payload = @[1'u8, 2, 3]
      localStorage = toSockaddrStorage(initTAddress("127.0.0.1:1000"))
      ipv4DestStorage = toSockaddrStorage(initTAddress("127.0.0.1:4433"))
      oversized = newSeq[byte](65536)
      iov = struct_iovec(iov_base: addr payload[0], iov_len: payload.len.csize_t)
      oversizedIov =
        struct_iovec(iov_base: addr oversized[0], iov_len: oversized.len.csize_t)
      specs = [
        makeOutSpec(addr iov, addr localStorage, addr ipv4DestStorage),
        makeOutSpec(addr oversizedIov, addr localStorage, addr ipv4DestStorage),
      ]

    let res = sendPacketsOut(cast[pointer](ctx), addr specs[0], 2)
    # Linux overwrites errno with EAGAIN here, the other platforms leave alone
    # whatever the failed send set.
    when defined(linux):
      check errno == EAGAIN

    check res == 1

  asyncTest "a batch larger than the adapter buffer sends every packet":
    # Exercise the adapter across its fixed-size descriptor buffer.
    const SpecCount = 64 + 1 # const is not exported

    let udp = newDatagramTransportSync(ignorePacket, local = AutoAddressIP4)
    defer:
      await udp.closeWait()

    let ctx = QuicContext(udp: udp)
    var
      payload = @[1'u8, 2, 3]
      localStorage = toSockaddrStorage(initTAddress("127.0.0.1:1000"))
      destStorage = toSockaddrStorage(initTAddress("127.0.0.1:4433"))
      iov = struct_iovec(iov_base: addr payload[0], iov_len: payload.len.csize_t)
      specs = newSeq[struct_lsquic_out_spec](SpecCount)
    for spec in specs.mitems:
      spec = makeOutSpec(addr iov, addr localStorage, addr destStorage)

    check sendPacketsOut(cast[pointer](ctx), addr specs[0], SpecCount.cuint) == SpecCount
