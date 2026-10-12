# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.used.}

import chronos, chronos/osdefs, chronos/unittest2/asynctests
import ../lsquic/context/io
when defined(windows):
  import ../lsquic/context/context
import ./helpers/trackers

suite "UDP receive":
  teardown:
    checkTrackers()

  asyncTest "drained IPv4 burst keeps the dual-stack socket family":
    proc ignore(
        udp: DatagramTransport, remote: TransportAddress
    ): Future[void] {.async: (raises: []).} =
      discard

    let
      server = newDatagramTransport6(
        ignore,
        local = initTAddress("[::]:0"),
        flags = {ServerFlags.NoAutoRead, ServerFlags.PacketInfo},
      )
      client = newDatagramTransport(ignore)
    defer:
      await allFutures(server.closeWait(), client.closeWait())

    when defined(windows):
      let ctx = QuicContext()
      check ctx.initPacketIo(SocketHandle(server.fd))

    var destination = initTAddress("127.0.0.1:0")
    destination.port = server.localAddress().port
    await client.sendTo(destination, @[1.byte])
    await client.sendTo(destination, @[2.byte])

    var buf = newSeq[byte](DefaultDatagramBufferSize)
    for expected in [1.byte, 2.byte]:
      var
        local, remote: TransportAddress
        received = -1

      for _ in 0 ..< 100:
        received =
          when defined(windows):
            recvPacket(
              ctx, SocketHandle(server.fd), buf, server.localAddress(), local, remote
            )
          else:
            recvPacket(
              SocketHandle(server.fd), buf, server.localAddress(), local, remote
            )
        if received >= 0:
          break
        # The socket is non-blocking and send completion may precede readability.
        await sleepAsync(10.milliseconds)

      check:
        received == 1
        buf[0] == expected
        local == destination.toIPv6()
        remote.family == AddressFamily.IPv4
