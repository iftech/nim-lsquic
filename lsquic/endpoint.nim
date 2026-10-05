# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

import chronos, chronicles, results
when defined(windows):
  from chronos/osdefs import SOL_SOCKET, SO_RCVBUF
else:
  from posix import SOL_SOCKET, SO_RCVBUF
import
  ./[
    errors, connection, tlsconfig, connectionmanager, lsquic_ffi, certificateverifier,
    socketconfig, engine_config,
  ]
import ./context/[server, client, context, io]
import ./helpers/[logging, transportaddr]
from chronos/osdefs import Sockaddr_storage, SockAddr, SockLen, SocketHandle
when defined(windows):
  from std/winlean import recvfrom
else:
  from chronos/osdefs import recvfrom

logScope:
  topics = "lsquic"

type
  QuicEndpointCapability* = enum
    CanListen
    CanDial

  QuicEndpointCapabilities* = set[QuicEndpointCapability]

  RouteTarget = enum
    rtClient
    rtServer

  QuicEndpoint* = ref object of RootObj
    tlsConfig: TLSConfig
    capabilities: QuicEndpointCapabilities
    serverContext: ServerContext
    clientContext: ClientContext
    connman: ConnectionManager
    udp: DatagramTransport
    stopped: bool
    drainBuf: seq[byte]
    engineConfig: QuicEngineConfig

const
  CloseWait: Duration = 300.milliseconds

  MaxDatagramsPerWakeup = 64
    ## Capped so that a busy socket cannot starve the rest of the event loop.

proc socketReceiveBufferBytes(
    udp: DatagramTransport
): int {.raises: [TransportOsError].} =
  let value = getSockOpt2(udp.fd, int(SOL_SOCKET), int(SO_RCVBUF)).valueOr:
    raiseTransportOsError(error)
    return
  value.int

proc configureReceiveBuffer(
    udp: DatagramTransport, socketConfig: QuicSocketConfig
) {.raises: [TransportOsError].} =
  let requested = socketConfig.receiveBufferBytes
  if requested == 0:
    # Zero keeps the OS default socket buffer.
    return

  let setRes = setSockOpt2(udp.fd, int(SOL_SOCKET), int(SO_RCVBUF), requested)
  if setRes.isErr():
    raiseTransportOsError(setRes.error())

  let effective = udp.socketReceiveBufferBytes()
  if effective < requested:
    when defined(linux):
      warn "UDP receive buffer is smaller than requested",
        requestedBytes = requested,
        effectiveBytes = effective,
        hint = "raise net.core.rmem_max if Linux caps SO_RCVBUF"
    else:
      warn "UDP receive buffer is smaller than requested",
        requestedBytes = requested, effectiveBytes = effective
  else:
    debug "Configured UDP receive buffer",
      requestedBytes = requested, effectiveBytes = effective

proc createServerContext(
    tlsConfig: TLSConfig, fd: cint, engineConfig: QuicEngineConfig
): ServerContext {.raises: [QuicError].} =
  var context = ServerContext.new(tlsConfig, engineConfig).valueOr:
    raise newException(QuicError, error)
  context.fd = fd
  context

proc createClientContext(
    tlsConfig: TLSConfig, fd: cint, engineConfig: QuicEngineConfig
): ClientContext {.raises: [QuicError].} =
  var context = ClientContext.new(tlsConfig, engineConfig).valueOr:
    raise newException(QuicError, error)
  context.fd = fd
  context

proc scidLen(endpoint: QuicEndpoint): cuint {.raises: [].} =
  if not endpoint.serverContext.isNil and
      endpoint.serverContext.settings.es_scid_len != 0:
    return endpoint.serverContext.settings.es_scid_len
  if not endpoint.clientContext.isNil and
      endpoint.clientContext.settings.es_scid_len != 0:
    return endpoint.clientContext.settings.es_scid_len
  LSQUIC_DF_SCID_LEN.cuint

proc packetDcid(
    endpoint: QuicEndpoint, packet: openArray[byte], cid: var CidKey
): bool {.raises: [].} =
  if packet.len == 0:
    return false

  var cidLen: uint8
  let offset = lsquic_dcid_from_packet(
    addr packet[0], packet.len.csize_t, endpoint.scidLen(), addr cidLen
  )
  if offset < 0:
    return false

  let start = offset.int
  if cidLen == 0 or cidLen.int > MAX_CID_LEN or start + cidLen.int > packet.len:
    return false

  cid = CidKey(len: cidLen)
  for i in 0 ..< cidLen.int:
    cid.bytes[i] = packet[start + i]
  true

const
  HeaderFormBit = 0b1000_0000'u8
  FixedBit = 0b0100_0000'u8
  HeaderBitsMask = HeaderFormBit or FixedBit
  LongPacketTypeMask = 0b0011_0000'u8

func isIetfInitial(packet: openArray[byte]): bool {.raises: [].} =
  if packet.len == 0:
    return false
  (packet[0] and HeaderBitsMask) == HeaderBitsMask and
    (packet[0] and LongPacketTypeMask) == 0

func isIetfShortHeader(packet: openArray[byte]): bool {.raises: [].} =
  ## IETF short headers have Header Form clear and Fixed Bit set.
  packet.len > 0 and (packet[0] and HeaderBitsMask) == FixedBit

proc routeDatagram(
    endpoint: QuicEndpoint, data: openArray[byte], local, remote: TransportAddress
): set[RouteTarget] {.raises: [].} =
  if endpoint.isNil or endpoint.stopped:
    return {}

  let
    hasClientContext = not endpoint.clientContext.isNil
    hasServerContext = not endpoint.serverContext.isNil

  # Only one engine on this socket, so there is nothing to disambiguate: skip
  # parsing the connection id out of every datagram and probing the CID set.
  if hasClientContext != hasServerContext:
    if hasClientContext:
      discard endpoint.clientContext.packetIn(data, local, remote)
      return {rtClient}
    discard endpoint.serverContext.packetIn(data, local, remote)
    return {rtServer}

  var cid: CidKey
  if endpoint.packetDcid(data, cid):
    if hasClientContext and endpoint.clientContext.ownsCid(cid):
      trace "Routing datagram to client context by connection ID", cid
      discard endpoint.clientContext.packetIn(data, local, remote)
      return {rtClient}

    if hasServerContext and endpoint.serverContext.ownsCid(cid):
      trace "Routing datagram to server context by connection ID", cid
      discard endpoint.serverContext.packetIn(data, local, remote)
      return {rtServer}

  if hasServerContext and data.isIetfInitial():
    trace "Routing Initial packet with unknown connection ID to server context",
      bytes = data.len, local, remote
    discard endpoint.serverContext.packetIn(data, local, remote)
    return {rtServer}

  if hasClientContext and hasServerContext and data.isIetfShortHeader():
    trace "Routing short-header packet with unknown connection ID to both contexts",
      bytes = data.len, local, remote
    discard endpoint.clientContext.packetIn(data, local, remote)
    discard endpoint.serverContext.packetIn(data, local, remote)
    return {rtClient, rtServer}

  trace "Dropping packet with unknown connection ID", bytes = data.len, local, remote
  {}

proc recvDatagram(
    fd: SocketHandle,
    buf: var seq[byte],
    remoteAddress: var Sockaddr_storage,
    remoteAddrLen: var SockLen,
): int {.raises: [].} =
  when defined(windows):
    recvfrom(
      fd,
      cast[cstring](addr buf[0]),
      cint(buf.len),
      cint(0),
      cast[ptr SockAddr](addr remoteAddress),
      addr remoteAddrLen,
    ).int
  else:
    recvfrom(
      fd,
      addr buf[0],
      buf.len,
      cint(0),
      cast[ptr SockAddr](addr remoteAddress),
      addr remoteAddrLen,
    ).int

proc drainDatagrams(
    endpoint: QuicEndpoint, udp: DatagramTransport, local: TransportAddress
): set[RouteTarget] {.raises: [].} =
  ## Chronos hands this callback a single datagram per event-loop wakeup, so
  ## whatever else has already arrived is read here rather than one wakeup, and
  ## one engine tick, at a time.
  if endpoint.drainBuf.len == 0:
    endpoint.drainBuf = newSeq[byte](DefaultDatagramBufferSize)

  var targets: set[RouteTarget]
  for _ in 0 ..< MaxDatagramsPerWakeup:
    var
      remoteAddress: Sockaddr_storage
      remoteAddrLen = SockLen(sizeof(Sockaddr_storage))
    let res = recvDatagram(
      SocketHandle(udp.fd), endpoint.drainBuf, remoteAddress, remoteAddrLen
    )
    if res < 0:
      # Empty, or an error the transport will report again on the next wakeup.
      break

    if res > 0:
      targets.incl endpoint.routeDatagram(
        endpoint.drainBuf.toOpenArray(0, res - 1),
        local,
        toTransportAddress(cast[ptr SockAddr](addr remoteAddress)),
      )

  targets

proc readIncoming(
    udp: DatagramTransport, msg: var seq[byte], msgLen: var int
) {.raises: [TransportError].} =
  ## Avoid `peekMessage` under ARC/ORC: without `shallowCopy`, Chronos copies the
  ## full receive buffer instead of only the datagram. `getMessage` copies only the
  ## received bytes.
  when declared(shallowCopy):
    udp.peekMessage(msg, msgLen)
  else:
    msg = udp.getMessage()
    msgLen = msg.len

proc receiveFromUdp(
    endpoint: QuicEndpoint, udp: DatagramTransport, remote: TransportAddress
) {.raises: [].} =
  var
    targets: set[RouteTarget]
    local: TransportAddress

  try:
    var
      msg: seq[byte]
      msgLen: int
    local = udp.localAddress()
    readIncoming(udp, msg, msgLen)
    if msgLen > 0:
      targets = endpoint.routeDatagram(msg.toOpenArray(0, msgLen - 1), local, remote)
  except TransportError as e:
    warn "Failed to read UDP datagram", error = shortLog(e.msg)
    return

  targets = targets + endpoint.drainDatagrams(udp, local)

  if rtClient in targets:
    endpoint.clientContext.processWhenReady()
  if rtServer in targets:
    endpoint.serverContext.processWhenReady()

proc createUdp(
    endpoint: QuicEndpoint, address: TransportAddress, socketConfig: QuicSocketConfig
): DatagramTransport {.raises: [QuicError, TransportOsError].} =
  proc onReceive(
      udp: DatagramTransport, remote: TransportAddress
  ) {.async: (raises: []).} =
    endpoint.receiveFromUdp(udp, remote)

  let udp =
    case address.family
    of AddressFamily.IPv4:
      newDatagramTransport(onReceive, local = address)
    of AddressFamily.IPv6:
      newDatagramTransport6(onReceive, local = address)
    else:
      raise newException(QuicError, "only IPv4/IPv6 address is supported")

  udp.configureReceiveBuffer(socketConfig)
  udp

proc new*(
    _: type QuicEndpoint,
    tlsConfig: TLSConfig,
    address: TransportAddress,
    capabilities: QuicEndpointCapabilities = {CanListen, CanDial},
    socketConfig: QuicSocketConfig = DefaultQuicSocketConfig,
    engineConfig: QuicEngineConfig = DefaultQuicEngineConfig,
): QuicEndpoint {.raises: [QuicConfigError, QuicError, TransportOsError].} =
  if CanListen in capabilities and tlsConfig.certificate.len == 0:
    raise newException(QuicConfigError, "tlsConfig does not contain a certificate")

  socketConfig.validate()
  if CanListen in capabilities:
    engineConfig.validate(true)
  if CanDial in capabilities:
    engineConfig.validate(false)

  var endpoint = QuicEndpoint(
    tlsConfig: tlsConfig,
    capabilities: capabilities,
    connman: ConnectionManager.new(),
    engineConfig: engineConfig,
  )
  endpoint.udp = endpoint.createUdp(address, socketConfig)

  var initialized = false

  defer:
    if not initialized:
      if not endpoint.serverContext.isNil:
        endpoint.serverContext.destroy()
      if not endpoint.clientContext.isNil:
        endpoint.clientContext.destroy()
      if not endpoint.udp.isNil:
        endpoint.udp.close()

  if CanListen in capabilities:
    endpoint.serverContext =
      createServerContext(tlsConfig, endpoint.udp.fd.cint, engineConfig)

  initialized = true
  endpoint

proc new*(
    _: type QuicEndpoint,
    tlsConfig: TLSConfig,
    family: AddressFamily,
    socketConfig: QuicSocketConfig = DefaultQuicSocketConfig,
    engineConfig: QuicEngineConfig = DefaultQuicEngineConfig,
): QuicEndpoint {.raises: [QuicConfigError, QuicError, TransportOsError].} =
  let address =
    case family
    of AddressFamily.IPv4:
      AnyAddress
    of AddressFamily.IPv6:
      AnyAddress6
    else:
      raise newException(QuicError, "endpoint supports only IPv4/IPv6 address")
  QuicEndpoint.new(tlsConfig, address, {CanDial}, socketConfig, engineConfig)

proc ensureClientContext(
    endpoint: QuicEndpoint
): ClientContext {.raises: [QuicError].} =
  if CanDial notin endpoint.capabilities:
    raise newException(QuicError, "endpoint is not dial-capable")

  if endpoint.clientContext.isNil:
    endpoint.clientContext = createClientContext(
      endpoint.tlsConfig, endpoint.udp.fd.cint, endpoint.engineConfig
    )

  endpoint.clientContext

proc accept*(
    endpoint: QuicEndpoint
): Future[Connection] {.async: (raises: [CancelledError, TransportError]).} =
  if CanListen notin endpoint.capabilities:
    raise newException(TransportError, "endpoint is not listen-capable")

  if endpoint.stopped or endpoint.serverContext.isNil:
    raise newException(TransportError, "endpoint is stopped")

  while true:
    let
      incomingFut = endpoint.serverContext.incoming.get()
      closedFut = endpoint.connman.closed
      raceFut = await race(closedFut, incomingFut)

    if raceFut == closedFut:
      await incomingFut.cancelAndWait()
      raise newException(TransportError, "endpoint is stopped")

    let quicConn = await incomingFut
    if quicConn.lsquicConn.isNil and quicConn.incoming.len == 0:
      debug "Dropping incoming connection that closed before acceptance"
      continue

    let conn = newIncomingConnection(endpoint.serverContext, quicConn)
    endpoint.connman.addConnection(conn)
    return conn

proc dial(
    endpoint: QuicEndpoint,
    address: TransportAddress,
    serverName: string,
    certVerifier: Opt[CertificateVerifier],
): Future[Connection] {.
    async: (raises: [CancelledError, QuicError, DialError, TransportOsError])
.} =
  let ctx = endpoint.ensureClientContext()
  let connection = newOutgoingConnection(
    ctx, endpoint.udp.localAddress(), address, serverName, certVerifier
  )
  endpoint.connman.addConnection(connection)
  var connected = false
  try:
    await connection.dial()
    connected = true
  finally:
    if not connected:
      endpoint.connman.removeConnection(connection)

  connection

proc validateServerName(serverName: string) {.raises: [QuicError].} =
  if serverName.len == 0:
    raise newException(QuicError, "server name is empty")
  for c in serverName:
    if c == '\0':
      raise newException(QuicError, "server name contains a null byte")

proc dial*(
    endpoint: QuicEndpoint, address: TransportAddress
): Future[Connection] {.
    async: (raises: [CancelledError, QuicError, DialError, TransportOsError])
.} =
  if endpoint.tlsConfig.certVerifier.isNone:
    raise newException(
      QuicError, "certificate verifier is required; use dial(address, certVerifier)"
    )

  await endpoint.dial(address, "", Opt.none(CertificateVerifier))

proc dial*(
    endpoint: QuicEndpoint, address: TransportAddress, serverName: string
): Future[Connection] {.
    async: (raises: [CancelledError, QuicError, DialError, TransportOsError])
.} =
  validateServerName(serverName)

  if endpoint.tlsConfig.certVerifier.isNone:
    raise newException(
      QuicError,
      "certificate verifier is required; use dial(address, serverName, certVerifier)",
    )

  await endpoint.dial(address, serverName, Opt.none(CertificateVerifier))

proc dial*(
    endpoint: QuicEndpoint, address: TransportAddress, certVerifier: CertificateVerifier
): Future[Connection] {.
    async: (raises: [CancelledError, QuicError, DialError, TransportOsError])
.} =
  if certVerifier.isNil:
    raise newException(QuicError, "certificate verifier is nil")

  await endpoint.dial(address, "", Opt.some(certVerifier))

proc dial*(
    endpoint: QuicEndpoint,
    address: TransportAddress,
    serverName: string,
    certVerifier: CertificateVerifier,
): Future[Connection] {.
    async: (raises: [CancelledError, QuicError, DialError, TransportOsError])
.} =
  validateServerName(serverName)
  if certVerifier.isNil:
    raise newException(QuicError, "certificate verifier is nil")

  await endpoint.dial(address, serverName, Opt.some(certVerifier))

proc localAddress*(
    endpoint: QuicEndpoint
): TransportAddress {.raises: [TransportOsError].} =
  endpoint.udp.localAddress()

proc datagramTransport*(endpoint: QuicEndpoint): DatagramTransport {.raises: [].} =
  endpoint.udp

proc stop*(endpoint: QuicEndpoint) {.async: (raises: [CancelledError]).} =
  if endpoint.stopped:
    return

  endpoint.stopped = true
  await noCancel endpoint.connman.stop()
  # Politely wait before closing udp so connection close packets can be sent.
  await noCancel sleepAsync(CloseWait)

  if not endpoint.clientContext.isNil:
    endpoint.clientContext.stop()
  if not endpoint.serverContext.isNil:
    endpoint.serverContext.stop()

  await noCancel endpoint.udp.closeWait()

  if not endpoint.clientContext.isNil:
    endpoint.clientContext.destroy()
    endpoint.clientContext = nil
  if not endpoint.serverContext.isNil:
    endpoint.serverContext.destroy()
    endpoint.serverContext = nil

when defined(lsquic_testing):
  proc connectionCount*(endpoint: QuicEndpoint): int {.raises: [].} =
    ## Test-only: number of connections tracked by this endpoint's manager.
    endpoint.connman.len

  export
    scidLen, packetDcid, isIetfInitial, isIetfShortHeader, routeDatagram, RouteTarget
