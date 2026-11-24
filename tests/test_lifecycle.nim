# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.used.}

import chronos, chronos/unittest2/asynctests, results
import lsquic
import lsquic/context/[client, context, io, server, stream]
import ./helpers/[address, certificate, clientserver, stream, trackers]
from lsquic/lsquic_ffi import
  lsquic_stream_ctx_t, lsquic_conn_t, lsquic_stream_t, LSQUIC_DF_INIT_MAX_STREAMS_BIDI

initializeLsquic(true, true)

const timeout = 2.seconds

suite "lifecycle":
  teardown:
    checkTrackers()

  test "client and server honor stateless resets":
    let
      tlsConfig = makeTLSConfig()
      clientCtx = ClientContext.new(tlsConfig).valueOr:
        raiseAssert error
      serverCtx = ServerContext.new(tlsConfig).valueOr:
        clientCtx.stop()
        clientCtx.destroy()
        raiseAssert error
    defer:
      clientCtx.stop()
      clientCtx.destroy()
      serverCtx.stop()
      serverCtx.destroy()

    check:
      clientCtx.settings.es_honor_prst == 1
      serverCtx.settings.es_honor_prst == 1

  asyncTest "listener stop makes accept fail":
    let server = makeServer()
    let listener = server.listen(AutoAddressIP4)
    let accepting = listener.accept()

    await listener.stop()

    expect TransportError:
      discard await accepting.wait(timeout)

  asyncTest "listener stop fails all pending accepts":
    let server = makeServer()
    let listener = server.listen(AutoAddressIP4)
    let accepting1 = listener.accept()
    let accepting2 = listener.accept()
    let accepting3 = listener.accept()

    await listener.stop()

    expect TransportError:
      discard await accepting1.wait(timeout)
    expect TransportError:
      discard await accepting2.wait(timeout)
    expect TransportError:
      discard await accepting3.wait(timeout)

  asyncTest "remote closure defers state and notification together":
    # The opaque handle is never passed to the native engine.
    let quicConn = QuicConnection(lsquicConn: cast[ptr lsquic_conn_t](1))
    let conn = newIncomingConnection(nil, quicConn)

    quicConn.onClose()
    quicConn.onClose = nil
    quicConn.lsquicConn = nil

    check not conn.isClosed
    check not conn.closedFuture().finished

    check (await conn.closedFuture().withTimeout(timeout))
    check conn.isClosed

  asyncTest "connection close propagates to peer":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    peers.outgoing.close()

    check (await peers.outgoing.closedFuture().withTimeout(timeout))
    check (await peers.incoming.closedFuture().withTimeout(timeout))
    check peers.incoming.isClosed

  asyncTest "accepted connection close propagates to peer":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    peers.incoming.close()

    check (await peers.incoming.closedFuture().withTimeout(timeout))
    check (await peers.outgoing.closedFuture().withTimeout(timeout))
    check peers.outgoing.isClosed

  asyncTest "cancelling a stream waiter preserves connection closure notification":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let waiting = peers.incoming.incomingStream()
    await waiting.cancelAndWait()
    check not peers.incoming.isClosed
    check not peers.incoming.closedFuture().finished

    let nextStream = peers.incoming.incomingStream()
    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[42'u8])
    let incomingStream = await nextStream.wait(timeout)
    var buf: array[1, byte]
    check (await incomingStream.readOnce(buf)) == 1
    check buf[0] == 42

    peers.outgoing.close()
    check (await peers.incoming.closedFuture().withTimeout(timeout))
    check peers.incoming.isClosed

  asyncTest "connection close resets the peer's stream":
    # TODO: vacp2p/nim-lsquic#136
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[1'u8])
    let incomingStream = await peers.incoming.incomingStream()
    var firstByte = newSeq[byte](1)
    check (await incomingStream.readOnce(firstByte)) == 1

    peers.outgoing.close()
    check (await peers.incoming.closedFuture().withTimeout(timeout))

    var buf = newSeq[byte](8)

    expect StreamResetError:
      discard await incomingStream.readOnce(buf).wait(timeout)

  asyncTest "connection abort fails the peer's stream without fin":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[1'u8])
    let incomingStream = await peers.incoming.incomingStream()
    var firstByte = newSeq[byte](1)
    check (await incomingStream.readOnce(firstByte)) == 1

    peers.outgoing.abort()
    check (await peers.incoming.closedFuture().withTimeout(timeout))

    var buf = newSeq[byte](8)
    expect StreamError:
      discard await incomingStream.readOnce(buf).wait(timeout)

  asyncTest "accept skips closed connection and client redials":
    let server = makeServer()
    let listener = server.listen(AutoAddressIP4)
    let address = listener.localAddress()
    let client = makeClient()
    var accepted: Future[Connection]
    var incomingStream: Future[Stream]
    defer:
      if not accepted.isNil and not accepted.finished:
        await accepted.cancelAndWait()
      if not incomingStream.isNil and not incomingStream.finished:
        await incomingStream.cancelAndWait()
      await allFutures(client.stop(), listener.stop())

    let stale = await client.dial(address)
    stale.abort()
    check (await stale.closedFuture().withTimeout(timeout))

    accepted = listener.accept()
    let outgoing = await client.dial(address)
    check (await accepted.withTimeout(timeout))
    let incoming = await accepted

    incomingStream = incoming.incomingStream()
    let outgoingStream = await outgoing.openStream()
    await outgoingStream.write(@[1'u8])
    check (await incomingStream.withTimeout(timeout))

    let acceptedStream = await incomingStream
    var buf = newSeq[byte](1)
    check (await acceptedStream.readOnce(buf)) == 1
    check buf[0] == 1

    await outgoingStream.close()
    await acceptedStream.close()
    outgoing.close()
    incoming.close()

  asyncTest "pending accept observes connection before immediate client close":
    let server = makeServer()
    let listener = server.listen(AutoAddressIP4)
    let client = makeClient()
    let accepted = listener.accept()
    defer:
      if not accepted.finished:
        await accepted.cancelAndWait()
      await allFutures(client.stop(), listener.stop())

    let outgoing = await client.dial(listener.localAddress())
    let outgoingStream = await outgoing.openStream()
    await outgoingStream.close()
    outgoing.close()

    check (await accepted.withTimeout(timeout))
    let incoming = await accepted
    check (await incoming.closedFuture().withTimeout(timeout))
    let incomingStream = incoming.incomingStream()
    expect ConnectionClosedError:
      discard await incoming.incomingStream().wait(timeout)

    let stream = await incomingStream
    var buf = newSeq[byte](1)
    expect StreamError:
      discard await stream.readOnce(buf)

  asyncTest "pending incoming stream survives immediate client close":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let incomingStream = peers.incoming.incomingStream()
    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.close()
    peers.outgoing.close()

    let stream = await incomingStream.wait(timeout)
    var buf = newSeq[byte](1)
    expect StreamError:
      discard await stream.readOnce(buf)

  asyncTest "client stop closes active connections":
    let peers = await connectPeers()

    await peers.client.stop()

    check (await peers.outgoing.closedFuture().withTimeout(timeout))
    check (await peers.incoming.closedFuture().withTimeout(timeout))

    peers.incoming.close()
    await peers.listener.stop()

  asyncTest "operations fail after connection close":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    peers.outgoing.close()
    check (await peers.outgoing.closedFuture().withTimeout(timeout))
    check (await peers.incoming.closedFuture().withTimeout(timeout))

    expect ConnectionClosedError:
      discard await peers.outgoing.openStream()

    expect ConnectionClosedError:
      discard await peers.incoming.incomingStream()

  asyncTest "abort wakes pending incoming stream":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let incomingWaiting = peers.incoming.incomingStream()
    peers.outgoing.abort()

    expect ConnectionClosedError:
      discard await incomingWaiting.wait(timeout)

  asyncTest "cancel pending outgoing streams clears queue":
    let quicConn = QuicConnection(incoming: newAsyncQueue[Stream]())
    let stream1 = Stream.new()
    let stream2 = Stream.new()
    let pending1 = quicConn.addPendingStream(stream1)
    let pending2 = quicConn.addPendingStream(stream2)

    quicConn.cancelPending()

    expect ConnectionError:
      await pending1.wait(timeout)
    expect ConnectionError:
      await pending2.wait(timeout)
    check quicConn.popPendingStream(nil).isNone()

  asyncTest "a cancelled pending stream is available to the next caller":
    let quicConn = QuicConnection(incoming: newAsyncQueue[Stream]())
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin
    let pending = quicConn.addPendingStream(stream)

    await pending.cancelAndWait()
    check pending.cancelled()

    var nativeStream = 0
    let native = cast[ptr lsquic_stream_t](addr nativeStream)
    let popped = quicConn.popPendingStream(native)
    check popped.isSome()
    let available = quicConn.takeAvailableStream()
    check available.isSome()
    check available.get() == stream
    check stream.quicStream == native

  asyncTest "openStream parks once the peer's stream credit is exhausted":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    var opened: seq[Stream]
    for _ in 0 ..< LSQUIC_DF_INIT_MAX_STREAMS_BIDI:
      opened.add(await peers.outgoing.openStream())

    let parked = peers.outgoing.openStream()
    check not (await parked.withTimeout(timeout))

    await parked.cancelAndWait()

  asyncTest "a cancelled parked openStream returns its stream credit slot":
    # Returns the stream credit available once every stream opened here is retired.
    proc creditAfterRetiringAll(cancellations: int): Future[int] {.async.} =
      let peers = await connectPeers()
      defer:
        await peers.stop()

      # The peer reads each stream to EOF and closes it, retiring that stream's credit.
      proc serve() {.async.} =
        var buf = newSeq[byte](1)
        for _ in 0 ..< LSQUIC_DF_INIT_MAX_STREAMS_BIDI:
          let stream = await peers.incoming.incomingStream()
          check (await stream.readOnce(buf)) == 0
          await stream.close()

      let serving = serve()

      # Exhaust the peer's initial stream credit.
      var opened: seq[Stream]
      for _ in 0 ..< LSQUIC_DF_INIT_MAX_STREAMS_BIDI:
        opened.add(await peers.outgoing.openStream())

      # Park an openStream on the exhausted credit, then cancel it.
      for _ in 0 ..< cancellations:
        let parked = peers.outgoing.openStream()
        check not (await parked.withTimeout(timeout))
        await parked.cancelAndWait()

      # Close+EOF every stream, retiring the stream credit they hold.
      var buf = newSeq[byte](1)
      for stream in opened:
        await stream.close()
        check (await stream.readOnce(buf)) == 0

      if not await serving.withTimeout(timeout):
        await serving.cancelAndWait()
      check serving.completed()

      # Open until the retired credit is exhausted again.
      var extra = 0
      while extra <= LSQUIC_DF_INIT_MAX_STREAMS_BIDI:
        let opening = peers.outgoing.openStream()
        if not await opening.withTimeout(timeout):
          await opening.cancelAndWait()
          break
        discard await opening
        inc extra
      extra

    check (await creditAfterRetiringAll(0)) == LSQUIC_DF_INIT_MAX_STREAMS_BIDI

    check (await creditAfterRetiringAll(1)) == LSQUIC_DF_INIT_MAX_STREAMS_BIDI

  asyncTest "abort after open stream still closes connection":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let opening = peers.outgoing.openStream()
    peers.outgoing.abort()
    check (await opening.withTimeout(timeout))
    let stream = await opening
    check (await peers.outgoing.closedFuture().withTimeout(timeout))

    expect StreamError:
      await stream.write(@[1'u8])

  asyncTest "write after close raises stream error":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[1'u8])
    let incomingStream = await peers.incoming.incomingStream()
    var kickoff = newSeq[byte](1)
    check (await incomingStream.readOnce(kickoff)) == 1
    check kickoff[0] == 1

    await outgoingStream.close()

    expect StreamError:
      await outgoingStream.write(@[1'u8])

    var buf = newSeq[byte](8)
    check (await incomingStream.readOnce(buf)) == 0
    await incomingStream.close()

  asyncTest "write callback after local shutdown does not abort stream":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[42'u8])
    let incomingStream = await peers.incoming.incomingStream()
    var firstByte = newSeq[byte](1)
    check (await incomingStream.readOnce(firstByte)) == 1
    await outgoingStream.close()

    onWrite(outgoingStream.quicStream, cast[ptr lsquic_stream_ctx_t](outgoingStream))

    check outgoingStream.readFailure.len == 0

  asyncTest "cancel pending write clears stream write task":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    # 16 MB exceeds the send window, so the write parks with a pending write task
    let writing = outgoingStream.write(makeData(16 * 1024 * 1024))

    check outgoingStream.toWrite.isSome

    await writing.cancelAndWait()

    check outgoingStream.toWrite.isNone()

  asyncTest "pointer write drains the queued path from the caller's buffer":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    # The buffer is owned by this test, not by the write. 16 MB exceeds the send
    # window, so the write parks and the engine drains the remainder straight
    # out of `sent` through on_write - never through a copy of it.
    var sent = makeData(16 * 1024 * 1024)
    let writing = outgoingStream.write(sent[0].addr, sent.len)

    check outgoingStream.toWrite.isSome

    let incomingStream = await peers.incoming.incomingStream()
    let reading = incomingStream.readAllChunked(64 * 1024)

    await writing
    await outgoingStream.close()

    checkEqual((await reading).data, sent)
    await incomingStream.close()

  asyncTest "cancel pending pointer write clears stream write task":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    var sent = makeData(16 * 1024 * 1024)
    let writing = outgoingStream.write(sent[0].addr, sent.len)

    check outgoingStream.toWrite.isSome

    # cancelAndWait, not cancel: the engine may still be reading `sent` until
    # the future actually finishes, which is when the borrow ends.
    await writing.cancelAndWait()

    check outgoingStream.toWrite.isNone()

  asyncTest "read once returns zero repeatedly after eof":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[9'u8, 8, 7, 6])
    let incomingStream = await peers.incoming.incomingStream()
    await outgoingStream.close()

    check (await incomingStream.readStreamTillEOF()) == @[9'u8, 8, 7, 6]

    var buf = newSeq[byte](8)
    check (await incomingStream.readOnce(buf)) == 0
    check (await incomingStream.readOnce(buf)) == 0
    await incomingStream.close()

  asyncTest "blocked read completes when peer half closes":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[42'u8])
    let incomingStream = await peers.incoming.incomingStream()
    var firstChunk = newSeq[byte](1)
    check (await incomingStream.readOnce(firstChunk)) == 1
    check firstChunk[0] == 42

    var buf = newSeq[byte](8)
    let reading = incomingStream.readOnce(buf)

    await sleepAsync(100.milliseconds)
    check not reading.finished

    await outgoingStream.close()

    check (await reading.withTimeout(timeout))
    check (await reading) == 0
    await incomingStream.close()

  asyncTest "EOF after local half close does not abort stream":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[42'u8])
    let incomingStream = await peers.incoming.incomingStream()

    var firstByte = newSeq[byte](1)
    check (await incomingStream.readOnce(firstByte)) == 1
    await incomingStream.close()

    var buf = newSeq[byte](8)
    let reading = incomingStream.readOnce(buf)
    await sleepAsync(100.milliseconds)
    check not reading.finished

    await outgoingStream.close()

    check (await reading.withTimeout(timeout))
    check (await reading) == 0
    check incomingStream.readFailure.len == 0

  asyncTest "close then EOF retires peer-initiated stream credit":
    const StreamCount = 120
    const StreamCreditTimeout = 30.seconds
    let peers = await connectPeers()
    defer:
      await peers.stop()

    proc openStreamWithTimeout(
        conn: Connection
    ): Future[Stream] {.async: (raises: [CancelledError, ConnectionError]).} =
      let opening = conn.openStream()
      if not await opening.withTimeout(StreamCreditTimeout):
        await opening.cancelAndWait()
        doAssert false,
          "timed out opening stream; close+EOF should retire stream credit"
      await opening

    proc serve() {.async.} =
      for i in 0 ..< StreamCount:
        let stream = await peers.incoming.incomingStream()
        var buf = newSeq[byte](1)
        check (await stream.readOnce(buf)) == 1
        check buf[0] == byte(i mod 256)

        await stream.write(@[byte((i + 1) mod 256)])
        await stream.close()
        check (await stream.readOnce(buf)) == 0

    let serving = serve()

    for i in 0 ..< StreamCount:
      let stream = await peers.outgoing.openStreamWithTimeout()
      await stream.write(@[byte(i mod 256)])
      await stream.close()

      var buf = newSeq[byte](1)
      check (await stream.readOnce(buf)) == 1
      check buf[0] == byte((i + 1) mod 256)
      check (await stream.readOnce(buf)) == 0

    if not await serving.withTimeout(StreamCreditTimeout):
      await serving.cancelAndWait()
      doAssert false,
        "timed out serving streams; close+EOF should not leave stream handlers blocked"
    await serving

  asyncTest "cancelled blocked read clears pending read":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let incomingWaiting = peers.incoming.incomingStream()
    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[1'u8])
    check (await incomingWaiting.withTimeout(timeout))
    let incomingStream = await incomingWaiting

    var firstByte = newSeq[byte](1)
    check (await incomingStream.readOnce(firstByte)) == 1
    check firstByte[0] == 1

    var cancelledBuf = newSeq[byte](8)
    let reading = incomingStream.readOnce(cancelledBuf)

    await sleepAsync(100.milliseconds)
    check not reading.finished
    check incomingStream.toRead.isSome

    await reading.cancelAndWait()

    check incomingStream.toRead.isNone()

    await outgoingStream.write(@[99'u8])
    await sleepAsync(100.milliseconds)
    check cancelledBuf[0] == 0

    var buf = newSeq[byte](1)
    let nextRead = incomingStream.readOnce(buf)
    check (await nextRead.withTimeout(timeout))
    check (await nextRead) == 1
    check buf[0] == 99
    await incomingStream.close()

  asyncTest "peer reset":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[1'u8])
    let incomingStream = await peers.incoming.incomingStream()

    var firstByte = newSeq[byte](1)
    check (await incomingStream.readOnce(firstByte)) == 1
    check firstByte[0] == 1

    var buf = newSeq[byte](8)
    let reading = incomingStream.readOnce(buf)

    outgoingStream.abort()

    check (await reading.withTimeout(timeout))
    check (await reading) == 0
    check incomingStream.isEof

    var isReset = false
    try:
      await incomingStream.write(@[2'u8])
    except StreamResetError as exc:
      isReset = true
      check exc.how == ResetWrite

    check isReset

  asyncTest "vanished peer fails the stream without a fin":
    # The peer's socket disappears mid-stream, so it never sends a FIN.
    let server = makeEndpoint(AutoAddressIP4)
    let client = makeDialEndpoint(AddressFamily.IPv4)
    defer:
      await allFutures(client.stop(), server.stop())

    let accepting = server.accept()
    let outgoing = await client.dial(server.localAddress())
    let incoming = await accepting

    let serverStream = await incoming.openStream()
    await serverStream.write(@[1'u8])

    let clientStream = await outgoing.incomingStream()
    var firstByte = newSeq[byte](1)
    check (await clientStream.readOnce(firstByte)) == 1

    await server.datagramTransport().closeWait()

    var buf = newSeq[byte](8)
    expect StreamError:
      discard await clientStream.readOnce(buf).wait(45.seconds)
    check not clientStream.isEof
    check not clientStream.resetByPeer

  asyncTest "zero length reads return zero":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin
    var empty: seq[byte] = @[]

    check (await stream.readOnce(empty)) == 0

  test "stream id direction bit identifies unidirectional streams":
    check:
      not isUnidirectional(0)
      not isUnidirectional(1)
      isUnidirectional(2)
      isUnidirectional(3)

  asyncTest "receive-only stream rejects writes locally":
    let stream = Stream.new(canWrite = false)
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin

    check:
      stream.canRead
      not stream.canWrite
      stream.closeWrite

    expect StreamError:
      await stream.write(@[])

    await stream.close()

  asyncTest "late datagrams are ignored after context stops":
    let verifier: CertificateVerifier = CustomCertificateVerifier.init(
      proc(serverName: string, derCertificates: seq[seq[byte]]): bool {.gcsafe.} =
        discard serverName
        derCertificates.len > 0
    )
    let tlsConfig =
      TLSConfig.new(testCertificate(), testPrivateKey(), @["test"], Opt.some(verifier))
    let ctx = ClientContext.new(tlsConfig).valueOr:
      raiseAssert error
    let local = initTAddress("127.0.0.1:12345")
    let remote = initTAddress("127.0.0.1:54321")

    ctx.stop()
    check not ctx.packetIn([1'u8, 2, 3], local, remote)
    ctx.processWhenReady()

    ctx.destroy()
    check not ctx.packetIn([4'u8, 5, 6], local, remote)
    ctx.processWhenReady()

  asyncTest "connection operations are guarded after context stops":
    let ctx = ClientContext.new(makeTLSConfig()).valueOr:
      raiseAssert error
    defer:
      ctx.destroy()

    # A stopped context must not act on any connection. We prove that by using an invalid connection pointer
    # While the context is stopped, the calls below must skip it, so the pointer is never used.
    # If a call went through, it would dereference the pointer and crash.
    # The pointer has to be non-nil: these calls already skip a nil connection.
    let quicConn = QuicConnection(lsquicConn: cast[ptr lsquic_conn_t](0xF00D))

    check ctx.isRunning()
    ctx.stop()
    check not ctx.isRunning()

    # While stopped, close and abort must do nothing (never reach the connection).
    ctx.close(quicConn)
    ctx.abort(quicConn)

    # While stopped, makeStream must fail cleanly instead of opening a stream.
    expect ConnectionClosedError:
      ctx.makeStream(quicConn)

  asyncTest "context destroy is idempotent":
    let ctx = ClientContext.new(makeTLSConfig()).valueOr:
      raiseAssert error

    ctx.stop()
    ctx.destroy()
    check not ctx.isRunning()

    # second destroy is a safe no-op: it must not free the engine or SSL_CTX twice.
    ctx.destroy()
    check not ctx.isRunning()

  asyncTest "listen-capable endpoint requires a certificate":
    # QuicEndpoint.new rejects a listen-capable endpoint with no certificate,
    # before any socket or context is created.
    expect QuicConfigError:
      discard QuicEndpoint.new(TLSConfig.new(), AutoAddressIP4, {CanListen})

  asyncTest "dial-only endpoint rejects accept":
    let endpoint = makeDialEndpoint(AddressFamily.IPv4)
    defer:
      await endpoint.stop()

    var rejected = false
    var message = ""
    try:
      discard await endpoint.accept()
    except TransportError as exc:
      rejected = true
      message = exc.msg

    # The stopped endpoint raises TransportError too, so the message is all
    # that separates it from a capability rejection.
    check:
      rejected
      message == "endpoint is not listen-capable"

  asyncTest "listen-only endpoint rejects dial":
    let endpoint = makeEndpoint(AutoAddressIP4, {CanListen})
    defer:
      await endpoint.stop()

    expect QuicError:
      discard await endpoint.dial(endpoint.localAddress()).wait(timeout)

  asyncTest "endpoint stop is idempotent":
    let endpoint = makeEndpoint(AutoAddressIP4)

    await endpoint.stop()
    # second stop is a safe no-op: the socket is not closed twice.
    await endpoint.stop()

  asyncTest "connection is auto-removed from manager after close":
    let server = makeEndpoint(AutoAddressIP4)
    let client = makeDialEndpoint(AddressFamily.IPv4)
    defer:
      await allFutures(client.stop(), server.stop())

    let accepting = server.accept()
    let outgoing = await client.dial(server.localAddress())
    let incoming = await accepting

    check:
      client.connectionCount == 1
      server.connectionCount == 1

    outgoing.close()
    check:
      await outgoing.closedFuture().withTimeout(timeout)
      await incoming.closedFuture().withTimeout(timeout)

    # Removal from the manager is scheduled on close; yield one tick so it runs
    # before we count.
    await sleepAsync(0.milliseconds)

    check:
      client.connectionCount == 0
      server.connectionCount == 0

  asyncTest "peer reset in both directions merges to read-write":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin

    onReset(nil, cast[ptr lsquic_stream_ctx_t](stream), 0.cint)
    check:
      stream.resetHow == ResetRead
      stream.readResetByPeer()
      not stream.writeResetByPeer()
      not stream.closeWrite

    onReset(nil, cast[ptr lsquic_stream_ctx_t](stream), 1.cint)
    check:
      stream.resetHow == ResetReadWrite
      stream.readResetByPeer()
      stream.writeResetByPeer()
      stream.closeWrite

  asyncTest "peer read reset fails a parked read":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin
    var buf = newSeq[byte](8)
    let doneFut =
      Future[int].Raising([CancelledError, StreamError]).init("test parked read")
    stream.toRead =
      Opt.some(ReadTask(data: buf[0].addr, dataLen: buf.len, doneFut: doneFut))

    onReset(nil, cast[ptr lsquic_stream_ctx_t](stream), 0.cint)

    check:
      stream.resetHow == ResetRead
      stream.toRead.isNone()

    expect StreamResetError:
      discard await doneFut.wait(timeout)

  asyncTest "peer write reset fails a parked write":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin
    var data = @[1'u8, 2, 3]
    let doneFut =
      Future[void].Raising([CancelledError, StreamError]).init("test parked write")
    stream.toWrite =
      Opt.some(WriteTask(data: data[0].addr, dataLen: data.len, doneFut: doneFut))

    onReset(nil, cast[ptr lsquic_stream_ctx_t](stream), 1.cint)

    check:
      stream.resetHow == ResetWrite
      stream.toWrite.isNone()

    expect StreamResetError:
      await doneFut.wait(timeout)

  asyncTest "read after read reset raises":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin
    stream.markResetByPeer(ResetRead)
    check stream.resetHow == ResetRead

    var buf = newSeq[byte](8)
    expect StreamResetError:
      discard await stream.readOnce(buf)

  asyncTest "nil read destination is rejected":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin

    expect AssertionDefect:
      discard await stream.readOnce(nil, 8)

  asyncTest "read waiting for the read lock sees the stream closed by the engine":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin
    # hold the lock so the read parks after its pre-lock checks have passed
    await stream.readLock.acquire()

    var buf = newSeq[byte](8)
    let reading = stream.readOnce(buf)

    stream.closedByEngine = true
    stream.readLock.release()

    # the post-lock re-check keeps the read away from the freed native stream
    check (await reading.withTimeout(timeout))
    expect StreamError:
      discard await reading

  asyncTest "read waiting for the read lock sees a peer reset":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin
    await stream.readLock.acquire()

    var buf = newSeq[byte](8)
    let reading = stream.readOnce(buf)

    stream.markResetByPeer(ResetRead)
    stream.readLock.release()

    expect StreamResetError:
      discard await reading.wait(timeout)

  asyncTest "write waiting for the write lock sees the stream closed by the engine":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin
    await stream.writeLock.acquire()

    let writing = stream.write(@[1'u8])

    stream.closedByEngine = true
    stream.writeLock.release()

    expect StreamError:
      await writing.wait(timeout)

  asyncTest "write waiting for the write lock sees a peer reset":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin
    await stream.writeLock.acquire()

    let writing = stream.write(@[1'u8])

    stream.markResetByPeer(ResetWrite)
    stream.writeLock.release()

    expect StreamResetError:
      await writing.wait(timeout)

  # One test per close path, pinning the rule that each settles the parked
  # operation itself.

  asyncTest "engine close without fin fails parked and later reads":
    let stream = Stream.new()
    var buf = newSeq[byte](8)
    let doneFut =
      Future[int].Raising([CancelledError, StreamError]).init("test parked read")
    stream.toRead =
      Opt.some(ReadTask(data: buf[0].addr, dataLen: buf.len, doneFut: doneFut))

    onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # also releases the pin

    check stream.toRead.isNone()
    check doneFut.finished
    expect StreamError:
      discard await doneFut.wait(timeout)

    var laterBuf = newSeq[byte](1)
    expect StreamError:
      discard await stream.readOnce(laterBuf)
    check not stream.isEof

  asyncTest "engine close fails a parked read after a peer read reset":
    let stream = Stream.new()
    stream.markResetByPeer(ResetRead)

    var buf = newSeq[byte](8)
    let doneFut =
      Future[int].Raising([CancelledError, StreamError]).init("test parked read")
    stream.toRead =
      Opt.some(ReadTask(data: buf[0].addr, dataLen: buf.len, doneFut: doneFut))

    onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # also releases the pin

    check stream.toRead.isNone()
    check doneFut.finished

    expect StreamResetError:
      discard await doneFut.wait(timeout)

  asyncTest "engine close fails a parked write after a local write shutdown":
    let stream = Stream.new()
    var data = @[1'u8, 2, 3]
    let doneFut =
      Future[void].Raising([CancelledError, StreamError]).init("test parked write")
    stream.toWrite =
      Opt.some(WriteTask(data: data[0].addr, dataLen: data.len, doneFut: doneFut))
    stream.closeWrite = true # pins the removed `if not closeWrite` guard

    onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # also releases the pin

    check stream.toWrite.isNone()
    check doneFut.finished

    expect StreamError:
      await doneFut.wait(timeout)

  asyncTest "abort settles a parked read and a parked write":
    let stream = Stream.new()
    defer:
      onClose(nil, cast[ptr lsquic_stream_ctx_t](stream)) # release the pin

    var buf = newSeq[byte](8)
    let readFut =
      Future[int].Raising([CancelledError, StreamError]).init("test parked read")
    stream.toRead =
      Opt.some(ReadTask(data: buf[0].addr, dataLen: buf.len, doneFut: readFut))

    var data = @[1'u8, 2, 3]
    let writeFut =
      Future[void].Raising([CancelledError, StreamError]).init("test parked write")
    stream.toWrite =
      Opt.some(WriteTask(data: data[0].addr, dataLen: data.len, doneFut: writeFut))

    stream.abort()

    # Unlike a received FIN, abort terminates the read side with an error.
    check not stream.isEof
    check stream.toRead.isNone()
    check stream.toWrite.isNone()
    check readFut.finished
    check writeFut.finished

    expect StreamError:
      discard await readFut.wait(timeout)
    expect StreamError:
      await writeFut.wait(timeout)

  asyncTest "connection close settles a parked write":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    # 16 MB exceeds the send window, so the write parks with a pending write task
    let writing = outgoingStream.write(makeData(16 * 1024 * 1024))

    check outgoingStream.toWrite.isSome

    peers.outgoing.close()

    expect StreamError:
      await writing.wait(timeout)

  asyncTest "concurrent reads on one stream are serialized":
    let peers = await connectPeers()
    defer:
      await peers.stop()

    let outgoingStream = await peers.outgoing.openStream()
    await outgoingStream.write(@[1'u8])
    let incomingStream = await peers.incoming.incomingStream()

    var firstByte = newSeq[byte](1)
    check:
      (await incomingStream.readOnce(firstByte)) == 1
      firstByte[0] == 1

    # A stream has a single pending-read slot, so `readLock` has to keep the
    # second reader out until the first one is done.
    var firstBuf = newSeq[byte](4)
    var secondBuf = newSeq[byte](8)
    let firstRead = incomingStream.readOnce(firstBuf)
    let secondRead = incomingStream.readOnce(secondBuf)

    # A parked read completes nothing, so there is no event to wait on.
    # The sleep is the window in which the second read would claim the slot
    # if `readLock` let it through.
    await sleepAsync(100.milliseconds)
    check:
      not firstRead.finished
      not secondRead.finished
      incomingStream.toRead.valueOr(ReadTask()).dataLen == firstBuf.len

    await outgoingStream.write(@[7'u8])
    check:
      (await firstRead.withTimeout(timeout))
      (await firstRead) == 1
      firstBuf[0] == 7

    # only now does the second read take the lock and claim the pending slot
    await sleepAsync(100.milliseconds)
    check:
      not secondRead.finished
      incomingStream.toRead.valueOr(ReadTask()).dataLen == secondBuf.len

    await outgoingStream.write(@[8'u8])
    check:
      (await secondRead.withTimeout(timeout))
      (await secondRead) == 1
      secondBuf[0] == 8

    await incomingStream.close()
