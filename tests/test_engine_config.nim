# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.used.}

import chronos, results, unittest2
import lsquic
import lsquic/context/[client, context, server]
import lsquic/lsquic_ffi
import ./helpers/[address, clientserver, trackers]

initializeLsquic(true, true)

suite "engine config":
  teardown:
    checkTrackers()

  test "empty config preserves role-specific defaults":
    var clientSettings, serverSettings: struct_lsquic_engine_settings
    lsquic_engine_init_settings(addr clientSettings, 0)
    lsquic_engine_init_settings(addr serverSettings, LSENG_SERVER)
    DefaultQuicEngineConfig.apply(clientSettings, false)
    DefaultQuicEngineConfig.apply(serverSettings, true)
    check:
      clientSettings.es_ping_period != serverSettings.es_ping_period
      clientSettings.es_idle_timeout == serverSettings.es_idle_timeout
      clientSettings.es_max_header_sets > 0
      serverSettings.es_max_header_sets > 0

  test "custom settings are applied with native units":
    var settings: struct_lsquic_engine_settings
    lsquic_engine_init_settings(addr settings, 0)
    let config = QuicEngineConfig(
      handshakeTimeout: Opt.some(5.seconds),
      idleTimeout: Opt.some(45.seconds),
      pingPeriod: Opt.some(10.seconds),
      noProgressTimeout: Opt.some(60.seconds),
      initialMaxData: Opt.some(4_000_000'u32),
      initialMaxStreamDataBidiLocal: Opt.some(1_000_000'u32),
      initialMaxStreamDataBidiRemote: Opt.some(2_000_000'u32),
      initialMaxStreamsBidi: Opt.some(256'u32),
      maxConnectionFlowControlWindow: Opt.some(8_000_000'u32),
      maxStreamFlowControlWindow: Opt.some(2_000_000'u32),
      congestionControl: Opt.some(Bbr),
      allowMigration: Opt.some(false),
      enablePathMtuDiscovery: Opt.some(true),
    )
    config.apply(settings, false)
    check:
      settings.es_handshake_to == 5_000_000
      settings.es_idle_timeout == 45
      settings.es_ping_period == 10
      settings.es_noprogress_timeout == 60
      settings.es_init_max_data == 4_000_000
      settings.es_init_max_streams_bidi == 256
      settings.es_cc_algo == Bbr.cuint
      settings.es_allow_migration == 0
      settings.es_dplpmtud == 1

  test "no-progress timeout is disabled unless set":
    for server in [false, true]:
      var unset, explicit: struct_lsquic_engine_settings
      unset.initSettings(server)
      explicit.initSettings(server)
      DefaultQuicEngineConfig.apply(unset, server)
      QuicEngineConfig(noProgressTimeout: Opt.some(30.seconds)).apply(explicit, server)
      check:
        unset.es_noprogress_timeout == 0
        explicit.es_noprogress_timeout == 30

  test "unsupported duration precision is rejected":
    var settings: struct_lsquic_engine_settings
    lsquic_engine_init_settings(addr settings, 0)
    let config = QuicEngineConfig(idleTimeout: Opt.some(1500.milliseconds))
    expect QuicConfigError:
      config.apply(settings, false)

  test "LSQUIC validation errors become config errors":
    var settings: struct_lsquic_engine_settings
    lsquic_engine_init_settings(addr settings, LSENG_SERVER)
    let config = QuicEngineConfig(idleTimeout: Opt.some(601.seconds))
    expect QuicConfigError:
      config.apply(settings, true)

  test "client setup rejects invalid engine settings before dialing":
    let config = QuicEngineConfig(idleTimeout: Opt.some(601.seconds))
    expect QuicConfigError:
      discard QuicClient.new(TLSConfig.new(), engineConfig = config)
    expect QuicConfigError:
      discard
        QuicEndpoint.new(TLSConfig.new(), AddressFamily.IPv4, engineConfig = config)

  test "listener setup rejects invalid engine settings":
    let config = QuicEngineConfig(idleTimeout: Opt.some(601.seconds))
    expect QuicConfigError:
      discard QuicEndpoint.new(makeTLSConfig(), AutoAddressIP4, engineConfig = config)

  test "contexts receive custom config":
    let config = QuicEngineConfig(initialMaxStreamsBidi: Opt.some(321'u32))
    let
      tlsConfig = makeTLSConfig()
      client = ClientContext.new(tlsConfig, config).valueOr:
        raiseAssert error
      server = ServerContext.new(tlsConfig, config).valueOr:
        client.stop()
        client.destroy()
        raiseAssert error
    defer:
      client.stop()
      client.destroy()
      server.stop()
      server.destroy()
    check:
      client.settings.es_init_max_streams_bidi == 321
      server.settings.es_init_max_streams_bidi == 321
