# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH 

{.used.}

import chronos, chronos/unittest2/asynctests, results, sequtils
import lsquic
import ./helpers/[address, clientserver, futures, stream, trackers]

initializeLsquic(true, true)

const
  dialTimeout = 5.seconds
  streamTimeout = 5.seconds

proc runConnectionTest(
    listenAddress: TransportAddress, dialAddress: TransportAddress
) {.async.} =
  let client = makeClient()
  let server = makeServer()
  let listener = server.listen(listenAddress)
  let boundAddress = listener.localAddress()
  # dial the requested address on the port the listener actually bound
  var effectiveDialAddress = dialAddress
  effectiveDialAddress.port = boundAddress.port
  defer:
    await allFutures(client.stop(), listener.stop())
  let accepting = listener.accept()
  let dialing = client.dial(effectiveDialAddress)

  let outgoingConn = await dialing
  let incomingConn = await accepting

  var staleRemote = effectiveDialAddress
  staleRemote.port = Port(1)
  outgoingConn.setCachedRemoteAddressForTest(staleRemote)

  check:
    outgoingConn.certificates().len == 1
    incomingConn.certificates().len == 1
    outgoingConn.remoteAddress().family == effectiveDialAddress.family
    outgoingConn.remoteAddress().port == effectiveDialAddress.port
    incomingConn.localAddress().family == boundAddress.family
    incomingConn.localAddress().port == boundAddress.port
    outgoingConn.localAddress().port == incomingConn.remoteAddress().port

  let outgoingBehaviour = proc() {.async.} =
    let stream = await outgoingConn.openStream()

    await stream.write(@[1'u8, 2, 3, 4, 5])
    await stream.write(@[6'u8, 7, 8, 9, 10])
    await stream.close()

  let incomingBehaviour = proc() {.async.} =
    let stream = await incomingConn.incomingStream()

    let received = await readStreamTillEOF(stream)

    check:
      received == @[1'u8, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      stream.isEof

    var buf = newSeq[byte](8)
    check (await stream.readOnce(buf)) == 0

    await stream.close()

  await allFuturesRaising(outgoingBehaviour(), incomingBehaviour()).wait(streamTimeout)

  outgoingConn.close()
  incomingConn.close()
  await allFutures(outgoingConn.closedFuture(), incomingConn.closedFuture())

  # Cannot create a stream once closed
  expect ConnectionClosedError:
    discard await outgoingConn.openStream()

proc runConnectionTest(address: TransportAddress) {.async.} =
  await runConnectionTest(address, address)

proc runLostInitialDialTest(address: TransportAddress) {.async.} =
  let server = makeServer()
  let listener = server.listen(address)
  let serverAddress = listener.localAddress()

  var
    clientAddress: TransportAddress
    dropped = 0
    proxyError: string

  # Drops the client's first datagram: the Initial that opens the handshake.
  proc onReceive(
      proxy: DatagramTransport, remote: TransportAddress
  ) {.async: (raises: []).} =
    try:
      let msg = proxy.getMessage()
      if remote != serverAddress:
        clientAddress = remote
        if dropped == 0:
          dropped.inc
          return
        await proxy.sendTo(serverAddress, msg)
      else:
        await proxy.sendTo(clientAddress, msg)
    except CatchableError as exc:
      proxyError = exc.msg

  let proxy = newDatagramTransport(onReceive, local = address)
  let client = makeClient()
  defer:
    await allFutures(client.stop(), listener.stop())
    await proxy.closeWait()

  let accepting = listener.accept()

  # The handshake gets through only if the engine retransmits the dropped Initial.
  let outgoingConn = await client.dial(proxy.localAddress()).wait(dialTimeout)
  let incomingConn = await accepting.wait(dialTimeout)

  check:
    dropped == 1
    proxyError.len == 0

  outgoingConn.close()
  incomingConn.close()
  await allFutures(outgoingConn.closedFuture(), incomingConn.closedFuture())

proc runClientAddressMigrationTest(address: TransportAddress) {.async.} =
  let server = makeServer()
  let listener = server.listen(address)
  let serverAddress = listener.localAddress()

  var
    clientAddress: TransportAddress
    useAlternatePath = false
    clientPacketsOnAlternatePath = 0
    serverPacketsOnAlternatePath = 0
    proxyError: string
    primaryProxy: DatagramTransport

  # After the handshake, forward client packets from the alternate proxy. Relay
  # replies through the primary proxy so only the server observes the rebinding.
  proc onAlternateReceive(
      proxy: DatagramTransport, remote: TransportAddress
  ) {.async: (raises: []).} =
    try:
      let msg = proxy.getMessage()
      if remote != serverAddress:
        proxyError = "alternate proxy received a packet from an unexpected peer"
        return
      serverPacketsOnAlternatePath.inc
      await primaryProxy.sendTo(clientAddress, msg)
    except CatchableError as exc:
      proxyError = exc.msg

  let alternateProxy = newDatagramTransport(onAlternateReceive, local = address)

  proc onPrimaryReceive(
      proxy: DatagramTransport, remote: TransportAddress
  ) {.async: (raises: []).} =
    try:
      let msg = proxy.getMessage()
      if remote == serverAddress:
        await proxy.sendTo(clientAddress, msg)
      else:
        clientAddress = remote
        if useAlternatePath:
          clientPacketsOnAlternatePath.inc
          await alternateProxy.sendTo(serverAddress, msg)
        else:
          await proxy.sendTo(serverAddress, msg)
    except CatchableError as exc:
      proxyError = exc.msg

  primaryProxy = newDatagramTransport(onPrimaryReceive, local = address)
  let client = makeClient()
  defer:
    await allFutures(client.stop(), listener.stop())
    await allFutures(primaryProxy.closeWait(), alternateProxy.closeWait())

  let accepting = listener.accept()
  let outgoingConn = await client.dial(primaryProxy.localAddress()).wait(dialTimeout)
  let incomingConn = await accepting.wait(dialTimeout)

  useAlternatePath = true
  let request = @[1'u8, 2, 3, 4, 5]
  let response = @[6'u8, 7, 8, 9, 10]

  let clientBehaviour = proc() {.async.} =
    let requestStream = await outgoingConn.openStream()
    await requestStream.write(request)
    await requestStream.close()

    let responseStream = await outgoingConn.incomingStream()
    check (await readStreamTillEOF(responseStream)) == response
    await responseStream.close()

  let serverBehaviour = proc() {.async.} =
    let requestStream = await incomingConn.incomingStream()
    check (await readStreamTillEOF(requestStream)) == request
    await requestStream.close()

    let responseStream = await incomingConn.openStream()
    await responseStream.write(response)
    await responseStream.close()

  await allFuturesRaising(clientBehaviour(), serverBehaviour()).wait(streamTimeout)

  check:
    proxyError.len == 0
    clientPacketsOnAlternatePath > 0
    serverPacketsOnAlternatePath > 0

  outgoingConn.close()
  incomingConn.close()
  await allFutures(outgoingConn.closedFuture(), incomingConn.closedFuture())

proc runEndpointAcceptTest(address: TransportAddress) {.async.} =
  let client = makeClient()
  let endpoint = makeEndpoint(address, {CanListen})
  let boundAddress = endpoint.localAddress()
  defer:
    await allFutures(client.stop(), endpoint.stop())

  let accepting = endpoint.accept()
  let outgoingConn = await client.dial(boundAddress)
  let incomingConn = await accepting

  check:
    outgoingConn.certificates().len == 1
    incomingConn.certificates().len == 1
    incomingConn.localAddress().port == boundAddress.port

  outgoingConn.close()
  incomingConn.close()
  await allFutures(outgoingConn.closedFuture(), incomingConn.closedFuture())

proc runEndpointSharedSocketDialTest(address: TransportAddress) {.async.} =
  let endpoint = makeEndpoint(address)
  let boundAddress = endpoint.localAddress()
  defer:
    await endpoint.stop()

  let accepting = endpoint.accept()
  let outgoingConn = await endpoint.dial(boundAddress)
  let incomingConn = await accepting

  check:
    outgoingConn.localAddress().port == boundAddress.port
    incomingConn.localAddress().port == boundAddress.port
    incomingConn.remoteAddress().port == boundAddress.port

  # The handshake completes without the cid lookup that later packets need.
  let outgoingBehaviour = proc() {.async.} =
    let stream = await outgoingConn.openStream()

    await stream.write(@[1'u8, 2, 3, 4, 5])
    await stream.close()

  let incomingBehaviour = proc() {.async.} =
    let stream = await incomingConn.incomingStream()

    check (await readStreamTillEOF(stream)) == @[1'u8, 2, 3, 4, 5]

    await stream.close()

  await allFuturesRaising(outgoingBehaviour(), incomingBehaviour()).wait(streamTimeout)

  outgoingConn.close()
  incomingConn.close()
  await allFutures(outgoingConn.closedFuture(), incomingConn.closedFuture())

proc runEndpointDialOnlyTest(address: TransportAddress) {.async.} =
  let server = makeServer()
  let listener = server.listen(address)
  let boundAddress = listener.localAddress()
  let endpoint = makeDialEndpoint(boundAddress.family)
  defer:
    await allFutures(listener.stop(), endpoint.stop())

  let accepting = listener.accept()
  let outgoingConn = await endpoint.dial(boundAddress)
  let incomingConn = await accepting

  check:
    outgoingConn.remoteAddress().port == boundAddress.port
    incomingConn.localAddress().port == boundAddress.port

  outgoingConn.close()
  incomingConn.close()
  await allFutures(outgoingConn.closedFuture(), incomingConn.closedFuture())

proc runEndpointSharedSocketCrossDialTest(address: TransportAddress) {.async.} =
  let endpointA = makeEndpoint(address)
  let endpointB = makeEndpoint(address)
  let addressA = endpointA.localAddress()
  let addressB = endpointB.localAddress()
  defer:
    await allFutures(endpointA.stop(), endpointB.stop())

  let acceptInitial = endpointB.accept()
  let initialOutgoing = await endpointA.dial(addressB)
  let initialIncoming = await acceptInitial

  check:
    initialOutgoing.localAddress().port == addressA.port
    initialOutgoing.remoteAddress().port == addressB.port
    initialIncoming.localAddress().port == addressB.port
    initialIncoming.remoteAddress().port == addressA.port

  let
    acceptA = endpointA.accept()
    acceptB = endpointB.accept()
    dialAtoB = endpointA.dial(addressB)
    dialBtoA = endpointB.dial(addressA)

  let
    outgoingAtoB = await dialAtoB.wait(dialTimeout)
    outgoingBtoA = await dialBtoA.wait(dialTimeout)
    incomingA = await acceptA.wait(dialTimeout)
    incomingB = await acceptB.wait(dialTimeout)

  check:
    outgoingAtoB.localAddress().port == addressA.port
    outgoingAtoB.remoteAddress().port == addressB.port
    outgoingBtoA.localAddress().port == addressB.port
    outgoingBtoA.remoteAddress().port == addressA.port
    incomingA.localAddress().port == addressA.port
    incomingA.remoteAddress().port == addressB.port
    incomingB.localAddress().port == addressB.port
    incomingB.remoteAddress().port == addressA.port

  let conns = @[
    initialOutgoing, initialIncoming, outgoingAtoB, outgoingBtoA, incomingA, incomingB
  ]
  for conn in conns:
    conn.close()

  await allFutures(conns.mapIt(it.closedFuture()))

proc runConcurrentStreamOpenTest(address: TransportAddress) {.async.} =
  const streamCount = 16

  let client = makeClient()
  let server = makeServer()
  let listener = server.listen(address)
  let boundAddress = listener.localAddress()
  defer:
    await allFutures(client.stop(), listener.stop())

  let accepting = listener.accept()
  let dialing = client.dial(boundAddress)

  let outgoingConn = await dialing
  let incomingConn = await accepting

  var received = newSeq[bool](streamCount)

  let receiveAll = proc() {.async.} =
    for _ in 0 ..< streamCount:
      let stream = await incomingConn.incomingStream()
      var id: array[1, byte]
      let n = await stream.readOnce(id[0].addr, id.len)
      check n == 1
      check id[0].int < streamCount
      received[id[0].int] = true
      await stream.close()

  var sendAll: seq[Future[void]]
  for i in 0 ..< streamCount:
    sendAll.add(
      (
        proc(idx: int): Future[void] {.async.} =
          let stream = await outgoingConn.openStream()
          await stream.write(@[byte(idx)])
          await stream.close()
      )(i)
    )

  await allFutures(receiveAll(), allFutures(sendAll)).wait(streamTimeout)

  for seen in received:
    check seen

proc runServerInitiatedStreamTest(address: TransportAddress) {.async.} =
  let client = makeClient()
  let server = makeServer()
  let listener = server.listen(address)
  let boundAddress = listener.localAddress()
  defer:
    await allFutures(client.stop(), listener.stop())

  let accepting = listener.accept()
  let dialing = client.dial(boundAddress)

  let outgoingConn = await dialing # client side
  let incomingConn = await accepting # server side

  # The accepting (server) side opens the stream, the dialing (client) side
  # receives it. This drives the server-initiated (odd stream id) parity.
  let serverBehaviour = proc() {.async.} =
    let stream = await incomingConn.openStream()

    await stream.write(@[1'u8, 2, 3, 4, 5])
    await stream.write(@[6'u8, 7, 8, 9, 10])
    await stream.close()

  let clientBehaviour = proc() {.async.} =
    let stream = await outgoingConn.incomingStream()

    let received = await readStreamTillEOF(stream)

    check:
      received == @[1'u8, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      stream.isEof

    var buf = newSeq[byte](8)
    check (await stream.readOnce(buf)) == 0

    await stream.close()

  await allFuturesRaising(serverBehaviour(), clientBehaviour()).wait(streamTimeout)

  outgoingConn.close()
  incomingConn.close()
  await allFutures(outgoingConn.closedFuture(), incomingConn.closedFuture())

proc runChunkedReadTest(peers: ConnectedPeers, bufSize, payloadSize: int) {.async.} =
  let payload = makeData(payloadSize)

  let sender = proc() {.async.} =
    let stream = await peers.outgoing.openStream()
    await stream.write(payload)
    await stream.close()

  let receiver = proc() {.async.} =
    let stream = await peers.incoming.incomingStream()
    let (received, reads) = await readAllChunked(stream, bufSize)

    # A single readOnce never returns more than bufSize bytes, so draining the
    # whole payload takes at least ceil(payloadSize / bufSize) reads.
    # Chunked delivery can split it into more reads than that.
    let minReads = (payloadSize + bufSize - 1) div bufSize

    checkEqual(received, payload)
    check:
      reads >= minReads
      stream.isEof

    var buf = newSeq[byte](bufSize)
    check (await stream.readOnce(buf)) == 0

    await stream.close()

  await allFuturesRaising(sender(), receiver()).wait(streamTimeout)

suite "connection":
  teardown:
    checkTrackers()

  asyncTest "ipv4":
    await runConnectionTest(AutoAddressIP4)

  asyncTest "ipv6":
    await runConnectionTest(AutoAddressIP6)

  asyncTest "ipv6 dual-stack listener accepts ipv4 dial":
    await runConnectionTest(WildcardIP6, AutoAddressIP4)

  asyncTest "dial completes when the initial packet is dropped":
    await runLostInitialDialTest(AutoAddressIP4)

  asyncTest "connection survives client address migration":
    await runClientAddressMigrationTest(AutoAddressIP4)

  asyncTest "multiple concurrent stream opens":
    await runConcurrentStreamOpenTest(AutoAddressIP4)

  asyncTest "server initiated stream reaches client incomingStream":
    await runServerInitiatedStreamTest(AutoAddressIP4)

  asyncTest "endpoint accepts inbound quic":
    await runEndpointAcceptTest(AutoAddressIP4)

  asyncTest "endpoint dials from listener socket":
    await runEndpointSharedSocketDialTest(AutoAddressIP4)

  asyncTest "dial-only endpoint works without listener":
    await runEndpointDialOnlyTest(AutoAddressIP4)

  asyncTest "endpoints cross-dial from shared listener sockets":
    await runEndpointSharedSocketCrossDialTest(AutoAddressIP4)

  asyncTest "reads reassemble payloads across buffer sizes":
    # (bufSize, payloadSize):
    #   (1, 10)     one byte at a time (max iterations)
    #   (3, 10)     undersized buffer, non-divisor
    #   (10, 10)    buffer exactly fits the payload
    #   (16, 10)    oversized buffer
    #   (100, 4096) non-divisor across the 4096 stream-buffer boundary
    const cases = [(1, 10), (3, 10), (10, 10), (16, 10), (100, 4096)]

    let peers = await connectPeers()
    defer:
      await peers.stop()

    for (bufSize, payloadSize) in cases:
      checkpoint("bufSize=" & $bufSize & " payloadSize=" & $payloadSize)
      await runChunkedReadTest(peers, bufSize, payloadSize)
