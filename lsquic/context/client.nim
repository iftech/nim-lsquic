# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH 

import boringssl
import results
import chronicles
import chronos
import chronos/osdefs
import ./[context, io, stream]
import
  ../[
    lsquic_ffi, errors, tlsconfig, timeout, stream, certificates, certificateverifier,
    tracking, engine_config,
  ]

logScope:
  topics = "lsquic"

proc onNewConn(
    stream_if_ctx: pointer, conn: ptr lsquic_conn_t
): ptr lsquic_conn_ctx_t {.cdecl.} =
  let details = connectionLogInfo(conn)
  debug "Client connection created",
    cid = details.cid,
    localAddress = details.localAddress,
    remoteAddress = details.remoteAddress
  let conn_ctx = lsquic_conn_get_ctx(conn)
  cast[ptr lsquic_conn_ctx_t](conn_ctx)

proc onHandshakeDone(
    conn: ptr lsquic_conn_t, status: enum_lsquic_hsk_status
) {.cdecl.} =
  let details = connectionLogInfo(conn)
  debug "Client handshake completed",
    cid = details.cid,
    localAddress = details.localAddress,
    remoteAddress = details.remoteAddress,
    status = handshakeStatusLabel(status)
  let conn_ctx = lsquic_conn_get_ctx(conn)
  if conn_ctx.isNil:
    trace "Client handshake completed without a connection context"
    return

  let quicClientConn = cast[QuicConnection](conn_ctx)
  if quicClientConn.connectedFut.finished:
    return

  if status == LSQ_HSK_FAIL or status == LSQ_HSK_RESUMED_FAIL:
    quicClientConn.connectedFut.fail(
      newException(DialError, "could not connect to server. Handshake failed")
    )
  else:
    let x509chain = lsquic_conn_get_full_cert_chain(quicClientConn.lsquicConn)
    let certChain = x509chain.getCertChain()
    x509chain.freeCertChain()
    quicClientConn.certChain = certChain

    quicClientConn.connectedFut.complete()

proc onConnClosed(conn: ptr lsquic_conn_t) {.cdecl.} =
  let (connStatus, msg) = connectionStatus(conn)
  let details = connectionLogInfo(conn)
  debug "Client connection closed",
    cid = details.cid,
    localAddress = details.localAddress,
    remoteAddress = details.remoteAddress,
    status = connectionStatusLabel(connStatus),
    statelessReset = connStatus == LSCONN_ST_RESET,
    reason = msg
  let conn_ctx = lsquic_conn_get_ctx(conn)
  if not conn_ctx.isNil:
    let quicClientConn = cast[QuicConnection](conn_ctx)
    if not quicClientConn.connectedFut.finished:
      # Not connected yet
      quicClientConn.connectedFut.fail(
        newException(
          DialError, "could not connect to server. Status: " & $connStatus & ". " & msg
        )
      )
    quicClientConn.cancelPending()
    quicClientConn.onClose()
    quicClientConn.onClose = nil
    quicClientConn.lsquicConn = nil
    quicClientConn.connectedFut = nil
    unpin(quicClientConn)
  lsquic_conn_set_ctx(conn, nil)

method dial*(
    ctx: ClientContext,
    local: TransportAddress,
    remote: TransportAddress,
    connectedFut: Future[void],
    onClose: proc() {.gcsafe, raises: [].},
    serverName: string,
    certVerifier: Opt[CertificateVerifier],
): Result[QuicConnection, string] {.raises: [], gcsafe.} =
  var
    localAddress: Sockaddr_storage
    localAddrLen: SockLen
    remoteAddress: Sockaddr_storage
    remoteAddrLen: SockLen

  local.toSAddr(localAddress, localAddrLen)
  remote.toSAddr(remoteAddress, remoteAddrLen)

  # TODO: should use constructor
  let quicClientConn = QuicConnection(
    isOutgoing: true,
    connectedFut: connectedFut,
    local: local,
    remote: remote,
    incoming: newAsyncQueue[Stream](),
    onClose: onClose,
    certVerifier: certVerifier,
  )
  pin(quicClientConn) # Keep it pinned until on_conn_closed is called
  let conn = lsquic_engine_connect(
    ctx.engine,
    N_LSQVER,
    cast[ptr SockAddr](addr localAddress),
    cast[ptr SockAddr](addr remoteAddress),
    cast[pointer](ctx),
    cast[ptr lsquic_conn_ctx_t](quicClientConn),
    if serverName.len == 0: nil else: serverName.cstring,
    0,
    nil,
    0,
    nil,
    0,
  )
  if conn.isNil:
    unpin(quicClientConn)
    return err("could not dial: " & $remote)

  quicClientConn.lsquicConn = conn
  ctx.trackConnectionCid(conn)
  ctx.processWhenReady()

  ok(quicClientConn)

proc new*(
    T: typedesc[ClientContext],
    tlsConfig: TLSConfig,
    engineConfig: QuicEngineConfig = DefaultQuicEngineConfig,
): Result[T, string] =
  var ctx = ClientContext()
  ctx.tlsConfig = tlsConfig
  ctx.running = true
  ctx.setupSSLContext()
  ctx.initCidTracking()

  ctx.settings.initSettings(false)

  try:
    engineConfig.apply(ctx.settings, false)
  except QuicConfigError:
    ctx.destroy()
    return err(getCurrentExceptionMsg())

  ctx.stream_if = struct_lsquic_stream_if(
    on_new_conn: onNewConn,
    on_hsk_done: onHandshakeDone,
    on_conn_closed: onConnClosed,
    on_new_stream: onNewStream,
    on_read: onRead,
    on_write: onWrite,
    on_close: onClose,
    on_reset: onReset,
  )
  ctx.api = struct_lsquic_engine_api(
    ea_settings: addr ctx.settings,
    ea_stream_if_ctx: cast[pointer](ctx),
    ea_packets_out_ctx: cast[pointer](ctx),
    ea_stream_if: addr ctx.stream_if,
    ea_get_ssl_ctx: getSSLCtx,
    ea_packets_out: sendPacketsOut,
  )
  ctx.api.ea_new_scids = addCids
  ctx.api.ea_live_scids = addCids
  ctx.api.ea_old_scids = removeCids
  ctx.api.ea_cids_update_ctx = cast[pointer](ctx)

  ctx.engine = lsquic_engine_new(0, addr ctx.api)
  if ctx.engine.isNil:
    ctx.destroy()
    return err("failed to create lsquic engine")

  ctx.tickTimeout = newTimeout(
    proc() =
      ctx.processWhenReady()
  )
  ctx.tickTimeout.set(Moment.now())

  return ok(ctx)
