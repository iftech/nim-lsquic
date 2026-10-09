# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

import chronos, results
import ./[errors, lsquic_ffi]

type
  CongestionControl* = enum
    Cubic = 1
    Bbr = 2
    Adaptive = 3

  QuicEngineConfig* = object
    handshakeTimeout*: Opt[Duration]
    idleTimeout*: Opt[Duration]
    pingPeriod*: Opt[Duration]
    noProgressTimeout*: Opt[Duration]
    initialMaxData*: Opt[uint32]
    initialMaxStreamDataBidiLocal*: Opt[uint32]
    initialMaxStreamDataBidiRemote*: Opt[uint32]
    initialMaxStreamsBidi*: Opt[uint32]
    maxConnectionFlowControlWindow*: Opt[uint32]
    maxStreamFlowControlWindow*: Opt[uint32]
    congestionControl*: Opt[CongestionControl]
    allowMigration*: Opt[bool]
    enablePathMtuDiscovery*: Opt[bool]

const DefaultQuicEngineConfig* = QuicEngineConfig()

func wholeUnits(
    value: Duration, nanosecondsPerUnit: int64, name: string
): uint64 {.raises: [QuicConfigError].} =
  if value.nanoseconds < 0:
    raise newException(QuicConfigError, name & " must be non-negative")
  if value.nanoseconds mod nanosecondsPerUnit != 0:
    raise newException(QuicConfigError, name & " must use whole units")
  uint64(value.nanoseconds div nanosecondsPerUnit)

proc apply*(
    config: QuicEngineConfig, settings: var struct_lsquic_engine_settings, server: bool
) {.raises: [QuicConfigError].} =
  template applySeconds(field, target, label: untyped) =
    if field.isSome:
      let value = wholeUnits(field.unsafeGet(), 1_000_000_000'i64, label)
      if value > high(cuint).uint64:
        raise newException(QuicConfigError, label & " is too large")
      target = value.cuint

  template applyUint(field, target: untyped) =
    if field.isSome:
      target = field.unsafeGet().cuint

  if config.handshakeTimeout.isSome:
    let value =
      wholeUnits(config.handshakeTimeout.unsafeGet(), 1_000'i64, "handshake timeout")
    if value > high(culong).uint64:
      raise newException(QuicConfigError, "handshake timeout is too large")
    settings.es_handshake_to = value.culong

  applySeconds(config.idleTimeout, settings.es_idle_timeout, "idle timeout")
  applySeconds(config.pingPeriod, settings.es_ping_period, "ping period")
  applySeconds(
    config.noProgressTimeout, settings.es_noprogress_timeout, "no-progress timeout"
  )

  applyUint(config.initialMaxData, settings.es_init_max_data)
  applyUint(
    config.initialMaxStreamDataBidiLocal, settings.es_init_max_stream_data_bidi_local
  )
  applyUint(
    config.initialMaxStreamDataBidiRemote, settings.es_init_max_stream_data_bidi_remote
  )
  applyUint(config.initialMaxStreamsBidi, settings.es_init_max_streams_bidi)
  applyUint(config.maxConnectionFlowControlWindow, settings.es_max_cfcw)
  applyUint(config.maxStreamFlowControlWindow, settings.es_max_sfcw)

  if config.congestionControl.isSome:
    settings.es_cc_algo = config.congestionControl.unsafeGet().cuint
  if config.allowMigration.isSome:
    settings.es_allow_migration = config.allowMigration.unsafeGet().cint
  if config.enablePathMtuDiscovery.isSome:
    settings.es_dplpmtud = config.enablePathMtuDiscovery.unsafeGet().cint

  var errorBuffer: array[256, char]
  let flags = if server: LSENG_SERVER.cuint else: 0.cuint
  if lsquic_engine_check_settings(
    addr settings, flags, cast[cstring](addr errorBuffer[0]), errorBuffer.len.csize_t
  ) != 0:
    raise newException(
      QuicConfigError,
      "invalid LSQUIC engine configuration: " & $cast[cstring](addr errorBuffer[0]),
    )

proc initSettings*(
    settings: var struct_lsquic_engine_settings, server: bool
) {.raises: [].} =
  let flags = if server: LSENG_SERVER.cuint else: 0.cuint
  lsquic_engine_init_settings(addr settings, flags)
  settings.es_versions = 1.cuint shl LSQVER_I001.cuint
  settings.es_cc_algo = Cubic.cuint
  settings.es_base_plpmtu = 1280
  settings.es_init_max_streams_bidi = 100
  settings.es_honor_prst = 1
  # lsquic's 60 s server default closes connections that carry only PINGs.
  settings.es_noprogress_timeout = 0
  settings.es_max_cfcw =
    if server:
      1536 * 1024
    else:
      8 * 1024 * 1024
  settings.es_max_sfcw =
    if server:
      1 * 1024 * 1024
    else:
      2 * 1024 * 1024
  settings.es_init_max_stream_data_bidi_local = 1024 * 1024
  settings.es_init_max_stream_data_bidi_remote = 1024 * 1024

proc validate*(config: QuicEngineConfig, server: bool) {.raises: [QuicConfigError].} =
  var settings: struct_lsquic_engine_settings
  settings.initSettings(server)
  config.apply(settings, server)
