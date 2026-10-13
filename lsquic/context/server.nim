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
    errors, lsquic_ffi, tlsconfig, timeout, stream, certificates, tracking,
    engine_config,
  ]
import ../helpers/transportaddr

logScope:
  topics = "lsquic"

proc onNewConn(
    stream_if_ctx: pointer, conn: ptr lsquic_conn_t
): ptr lsquic_conn_ctx_t {.cdecl.} =
  let details = connectionLogInfo(conn)
  debug "Server connection established",
    cid = details.cid,
    localAddress = details.localAddress,
    remoteAddress = details.remoteAddress
  var local: ptr SockAddr
  var remote: ptr SockAddr
  discard lsquic_conn_get_sockaddr(conn, addr local, addr remote)

  let x509chain = lsquic_conn_get_full_cert_chain(conn)
  let certChain = x509chain.getCertChain()
  x509chain.freeCertChain()

  # TODO: should use a constructor
  let quicConn = QuicConnection(
    isOutgoing: false,
    incoming: newAsyncQueue[Stream](),
    local: local.toTransportAddress(),
    remote: remote.toTransportAddress(),
    lsquicConn: conn,
    certChain: certChain,
    onClose: proc() =
      discard,
  )
  let serverCtx = cast[ServerContext](stream_if_ctx)
  serverCtx.trackConnectionCid(conn)
  pin(quicConn) # Keep it pinned until on_conn_closed is called
  serverCtx.incoming.putNoWait(quicConn)
  cast[ptr lsquic_conn_ctx_t](quicConn)

proc onConnClosed(conn: ptr lsquic_conn_t) {.cdecl.} =
  let (connStatus, msg) = connectionStatus(conn)
  let details = connectionLogInfo(conn)
  debug "Server connection closed",
    cid = details.cid,
    localAddress = details.localAddress,
    remoteAddress = details.remoteAddress,
    status = connectionStatusLabel(connStatus),
    statelessReset = connStatus == LSCONN_ST_RESET,
    reason = msg
  let conn_ctx = lsquic_conn_get_ctx(conn)
  if not conn_ctx.isNil:
    let quicConn = cast[QuicConnection](conn_ctx)
    quicConn.cancelPending()
    quicConn.onClose()
    quicConn.onClose = nil
    quicConn.lsquicConn = nil
    unpin(quicConn)
  lsquic_conn_set_ctx(conn, nil)

proc new*(
    T: typedesc[ServerContext],
    tlsConfig: TLSConfig,
    engineConfig: QuicEngineConfig = DefaultQuicEngineConfig,
): Result[T, string] =
  var ctx = ServerContext()
  ctx.tlsConfig = tlsConfig
  ctx.running = true
  ctx.incoming = newAsyncQueue[QuicConnection]()
  ctx.setupSSLContext()
  ctx.initCidTracking()

  ctx.settings.initSettings(true)

  try:
    engineConfig.apply(ctx.settings, true)
  except QuicConfigError:
    ctx.destroy()
    return err(getCurrentExceptionMsg())

  ctx.stream_if = struct_lsquic_stream_if(
    on_new_conn: onNewConn,
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

  ctx.engine = lsquic_engine_new(LSENG_SERVER, addr ctx.api)
  if ctx.engine.isNil:
    ctx.destroy()
    return err("failed to create lsquic engine")

  ctx.tickTimeout = newTimeout(
    proc() =
      ctx.processWhenReady()
  )
  ctx.tickTimeout.set(Moment.now())

  return ok(ctx)
