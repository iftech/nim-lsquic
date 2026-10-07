# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

when defined(windows):
  {.passl: "-lws2_32".}
  when defined(clang):
    {.passl: "-lpthread".}

when defined(release):
  when defined(vcc):
    {.passc: "/DNDEBUG".}
  else:
    {.passc: "-DNDEBUG".}

import std/[os, strutils]
import chronos/osdefs
{.push warning[UnusedImport]: off.}
import zlib
{.pop.}
import boringssl

include lsquic/lsquic_ffi_types

# use rsplit as a workaround for cross compilation path separator issue
const root = currentSourcePath.rsplit({DirSep, AltSep}, 2)[0]
const lsquicInclude = root & "/libs/lsquic/include"
const liblsquicInclude = root & "/libs/lsquic/src/liblsquic"
const lsqpack = root & "/libs/lsquic/src/liblsquic/ls-qpack"
const lshpack = root & "/libs/lsquic/src/lshpack"
const xxhash = root & "/libs/lsquic/src/lshpack/deps/xxhash"

when defined(windows):
  const wincompat = root & "/libs/lsquic/wincompat"
  {.passc: "-I" & wincompat.}

{.passc: "-I" & lsquicInclude.}
{.passc: "-I" & liblsquicInclude.}
{.passc: "-I" & lsqpack.}
{.passc: "-I" & lshpack.}
{.passc: "-I" & xxhash.}

const HAVE_BORINGSSL = "-DHAVE_BORINGSSL"
const XXH_HEADER_NAME = "-DXXH_HEADER_NAME=\"<lsquic_xxhash.h>\""

{.compile: "../libs/lsquic/src/liblsquic/lsquic_xxhash.c".}
{.compile("../libs/lsquic/src/liblsquic/ls-qpack/lsqpack.c", XXH_HEADER_NAME).}
{.compile("../libs/lsquic/src/lshpack/lshpack.c", XXH_HEADER_NAME).}
{.compile: "../libs/lsquic/src/liblsquic/ls-sfparser.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_adaptive_cc.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_alarmset.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_arr.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_attq.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_bbr.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_bw_sampler.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_cfcw.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_chsk_stream.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_conn.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_crand.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_crt_compress.c".}
{.compile("../libs/lsquic/src/liblsquic/lsquic_crypto.c", HAVE_BORINGSSL).}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_cubic.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_di_error.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_di_hash.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_di_nocopy.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_enc_sess_common.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_enc_sess_ietf.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_eng_hist.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_engine.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_ev_log.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_frab_list.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_frame_common.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_frame_reader.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_frame_writer.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_full_conn.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_full_conn_ietf.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_global.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_handshake.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_hash.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_hcsi_reader.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_hcso_writer.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_headers_stream.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_hkdf.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_hpi.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_hspack_valid.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_http.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_http1x_if.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_logger.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_malo.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_min_heap.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_mini_conn.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_mini_conn_ietf.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_minmax.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_mm.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_pacer.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_packet_common.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_packet_gquic.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_packet_in.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_packet_out.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_packet_resize.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_parse_Q046.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_parse_Q050.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_parse_common.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_parse_gquic_be.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_parse_gquic_common.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_parse_ietf_v1.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_parse_iquic_common.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_pr_queue.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_purga.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_qdec_hdl.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_qenc_hdl.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_qlog.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_qpack_exp.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_rechist.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_rtt.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_send_ctl.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_senhist.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_set.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_sfcw.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_shsk_stream.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_spi.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_stock_shi.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_str.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_stream.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_tokgen.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_trans_params.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_trechist.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_util.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_varint.c".}
{.compile: "../libs/lsquic/src/liblsquic/lsquic_version.c".}

type struct_lsquic_stream* = object
type struct_lsquic_conn* = object
type buf* = object
type struct_lsxpack_header* = object
type LSQUIC_DF_CFCW_SERVER* = object
type struct_lsquic_stream_ctx* = object
type struct_lsquic_conn_ctx* = object
type LSQUIC_DF_SFCW_SERVER* = object
type struct_lsquic_engine* = object
type LSQUIC_DF_SFCW_CLIENT* = object
type LSQUIC_DF_CFCW_CLIENT* = object
type
  lsquic_stream_id_t* = uint64
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic_types.h:40:18
  lsquic_engine_t* = struct_lsquic_engine
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic_types.h:43:30
  lsquic_conn_t* = struct_lsquic_conn
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic_types.h:46:28
  lsquic_conn_ctx_t* = struct_lsquic_conn_ctx
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic_types.h:49:32
  lsquic_stream_t* = struct_lsquic_stream
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic_types.h:52:30
  lsquic_stream_ctx_t* = struct_lsquic_stream_ctx
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic_types.h:55:34
  lsquic_http_headers_t* = struct_lsquic_http_headers
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic_types.h:58:36
  struct_lsquic_http_headers* {.pure, inheritable, bycopy.} = object
    count*: cint
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1784:8
    headers*: ptr struct_lsxpack_header

  struct_lsquic_stream_if* {.pure, inheritable, bycopy.} = object
    on_new_conn*:
      proc(a0: pointer, a1: ptr lsquic_conn_t): ptr lsquic_conn_ctx_t {.cdecl.}
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:165:8
    on_goaway_received*: proc(a0: ptr lsquic_conn_t): void {.cdecl.}
    on_conn_closed*: proc(a0: ptr lsquic_conn_t): void {.cdecl.}
    on_new_stream*:
      proc(a0: pointer, a1: ptr lsquic_stream_t): ptr lsquic_stream_ctx_t {.cdecl.}
    on_read*: proc(a0: ptr lsquic_stream_t, a1: ptr lsquic_stream_ctx_t): void {.cdecl.}
    on_write*:
      proc(a0: ptr lsquic_stream_t, a1: ptr lsquic_stream_ctx_t): void {.cdecl.}
    on_close*:
      proc(a0: ptr lsquic_stream_t, a1: ptr lsquic_stream_ctx_t): void {.cdecl.}
    on_dg_write*:
      proc(a0: ptr lsquic_conn_t, a1: pointer, a2: csize_t): ssize_t {.cdecl.}
    on_datagram*: proc(a0: ptr lsquic_conn_t, a1: pointer, a2: csize_t): void {.cdecl.}
    on_hsk_done*:
      proc(a0: ptr lsquic_conn_t, a1: enum_lsquic_hsk_status): void {.cdecl.}
    on_new_token*:
      proc(a0: ptr lsquic_conn_t, a1: ptr uint8, a2: csize_t): void {.cdecl.}
    on_sess_resume_info*:
      proc(a0: ptr lsquic_conn_t, a1: ptr uint8, a2: csize_t): void {.cdecl.}
    on_reset*: proc(
      a0: ptr lsquic_stream_t, a1: ptr lsquic_stream_ctx_t, a2: cint
    ): void {.cdecl.}
    on_conncloseframe_received*: proc(
      a0: ptr lsquic_conn_t, a1: cint, a2: uint64, a3: cstring, a4: cint
    ): void {.cdecl.}
    on_hset_in*:
      proc(a0: ptr lsquic_stream_t, a1: ptr lsquic_stream_ctx_t): void {.cdecl.}

  ssize_t* = compiler_ssize_t
    ## Generated based on /usr/include/x86_64-linux-gnu/sys/types.h:108:19
  lsquic_lookup_cert_f* =
    proc(a0: pointer, a1: ptr SockAddr, a2: cstring): ptr struct_ssl_ctx_st {.cdecl.}
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:266:31
  struct_lsquic_engine_settings* {.pure, inheritable, bycopy.} = object
    es_versions*: cuint
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:504:8
    es_cfcw*: cuint
    es_sfcw*: cuint
    es_max_cfcw*: cuint
    es_max_sfcw*: cuint
    es_max_streams_in*: cuint
    es_handshake_to*: culong
    es_idle_conn_to*: culong
    es_silent_close*: cint
    es_max_header_list_size*: cuint
    es_ua*: cstring
    es_sttl*: uint64
    es_pdmd*: uint32
    es_aead*: uint32
    es_kexs*: uint32
    es_max_inchoate*: cuint
    es_support_srej*: cint
    es_max_crypto_stash*: uint8
    es_support_push*: cint
    es_support_tcid0*: cint
    es_support_nstp*: cint
    es_honor_prst*: cint
    es_send_prst*: cint
    es_progress_check*: cuint
    es_rw_once*: cint
    es_proc_time_thresh*: cuint
    es_pace_packets*: cint
    es_clock_granularity*: cuint
    es_cc_algo*: cuint
    es_cc_rtt_thresh*: cuint
    es_enable_bw_sampler*: cint
    es_noprogress_timeout*: cuint
    es_init_max_data*: cuint
    es_init_max_stream_data_bidi_remote*: cuint
    es_init_max_stream_data_bidi_local*: cuint
    es_init_max_stream_data_uni*: cuint
    es_init_max_streams_bidi*: cuint
    es_init_max_streams_uni*: cuint
    es_idle_timeout*: cuint
    es_ping_period*: cuint
    es_scid_len*: cuint
    es_scid_iss_rate*: cuint
    es_qpack_dec_max_size*: cuint
    es_qpack_dec_max_blocked*: cuint
    es_qpack_enc_max_size*: cuint
    es_qpack_enc_max_blocked*: cuint
    es_ecn*: cint
    es_allow_migration*: cint
    es_retry_token_duration*: cuint
    es_ql_bits*: cint
    es_spin*: cint
    es_delayed_acks*: cint
    es_timestamps*: cint
    es_max_udp_payload_size_rx*: cushort
    es_grease_quic_bit*: cint
    es_dplpmtud*: cint
    es_base_plpmtu*: cushort
    es_max_plpmtu*: cushort
    es_mtu_probe_timer*: cuint
    es_datagrams*: cint
    es_optimistic_nat*: cint
    es_ext_http_prio*: cint
    es_qpack_experiment*: cint
    es_ptpc_periodicity*: cuint
    es_ptpc_max_packtol*: cuint
    es_ptpc_dyn_target*: cint
    es_ptpc_target*: cfloat
    es_ptpc_prop_gain*: cfloat
    es_ptpc_int_gain*: cfloat
    es_ptpc_err_thresh*: cfloat
    es_ptpc_err_divisor*: cfloat
    es_delay_onclose*: cint
    es_max_batch_size*: cuint
    es_max_delayed_0rtt_packets*: cuint
    es_check_tp_sanity*: cint
    es_amp_factor*: cint
    es_send_verneg*: cint
    es_preferred_address*: array[24'i64, uint8]
    es_max_header_sets*: cuint

  struct_lsquic_out_spec* {.pure, inheritable, bycopy.} = object
    iov*: ptr struct_iovec
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1254:8
    iovlen*: csize_t
    local_sa*: ptr SockAddr
    dest_sa*: ptr SockAddr
    peer_ctx*: pointer
    conn_ctx*: ptr lsquic_conn_ctx_t
    ecn*: cint

  struct_iovec* {.pure, inheritable, bycopy.} = object
    iov_base*: pointer
      ## Generated based on /usr/include/x86_64-linux-gnu/bits/types/struct_iovec.h:26:8
    iov_len*: csize_t

  lsquic_packets_out_f* =
    proc(a0: pointer, a1: ptr struct_lsquic_out_spec, a2: cuint): cint {.cdecl.}
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1278:15
  struct_lsquic_shared_hash_if* {.pure, inheritable, bycopy.} = object
    shi_insert*: proc(
      a0: pointer, a1: pointer, a2: cuint, a3: pointer, a4: cuint, a5: time_t
    ): cint {.cdecl.}
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1288:8
    shi_delete*: proc(a0: pointer, a1: pointer, a2: cuint): cint {.cdecl.}
    shi_lookup*: proc(
      a0: pointer, a1: pointer, a2: cuint, a3: ptr pointer, a4: ptr cuint
    ): cint {.cdecl.}

  time_t* = compiler_time_t
    ## Generated based on /usr/include/x86_64-linux-gnu/bits/types/time_t.h:10:18
  struct_lsquic_packout_mem_if* {.pure, inheritable, bycopy.} = object
    pmi_allocate*: proc(
      a0: pointer, a1: pointer, a2: ptr lsquic_conn_ctx_t, a3: cushort, a4: cschar
    ): pointer {.cdecl.}
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1326:8
    pmi_release*:
      proc(a0: pointer, a1: pointer, a2: pointer, a3: cschar): void {.cdecl.}
    pmi_return*: proc(a0: pointer, a1: pointer, a2: pointer, a3: cschar): void {.cdecl.}

  lsquic_cids_update_f* =
    proc(a0: pointer, a1: ptr pointer, a2: ptr lsquic_cid_t, a3: cuint): void {.cdecl.}
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1347:16
  struct_lsquic_hset_if* {.pure, inheritable, bycopy.} = object
    hsi_create_header_set*:
      proc(a0: pointer, a1: ptr lsquic_stream_t, a2: cint): pointer {.cdecl.}
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1365:8
    hsi_prepare_decode*: proc(
      a0: pointer, a1: ptr struct_lsxpack_header, a2: csize_t
    ): ptr struct_lsxpack_header {.cdecl.}
    hsi_process_header*:
      proc(a0: pointer, a1: ptr struct_lsxpack_header): cint {.cdecl.}
    hsi_discard_header_set*: proc(a0: pointer): void {.cdecl.}
    hsi_flags*: enum_lsquic_hsi_flag

  struct_lsquic_engine_api* {.pure, inheritable, bycopy.} = object
    ea_settings*: ptr struct_lsquic_engine_settings
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1438:8
    ea_stream_if*: ptr struct_lsquic_stream_if
    ea_stream_if_ctx*: pointer
    ea_packets_out*: lsquic_packets_out_f
    ea_packets_out_ctx*: pointer
    ea_lookup_cert*: lsquic_lookup_cert_f
    ea_cert_lu_ctx*: pointer
    ea_get_ssl_ctx*:
      proc(a0: pointer, a1: ptr SockAddr): ptr struct_ssl_ctx_st {.cdecl.}
    ea_shi*: ptr struct_lsquic_shared_hash_if
    ea_shi_ctx*: pointer
    ea_pmi*: ptr struct_lsquic_packout_mem_if
    ea_pmi_ctx*: pointer
    ea_new_scids*: lsquic_cids_update_f
    ea_live_scids*: lsquic_cids_update_f
    ea_old_scids*: lsquic_cids_update_f
    ea_cids_update_ctx*: pointer
    ea_verify_cert*: proc(a0: pointer, a1: ptr struct_stack_st_X509): cint {.cdecl.}
    ea_verify_ctx*: pointer
    ea_hsi_if*: ptr struct_lsquic_hset_if
    ea_hsi_ctx*: pointer
    ea_stats_fh*: pointer
    ea_alpn*: cstring
    ea_generate_scid*:
      proc(a0: pointer, a1: ptr lsquic_conn_t, a2: ptr uint8, a3: cuint): void {.cdecl.}
    ea_gen_scid_ctx*: pointer

  struct_lsquic_reader* {.pure, inheritable, bycopy.} = object
    lsqr_read*: proc(a0: pointer, a1: pointer, a2: csize_t): csize_t {.cdecl.}
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1743:8
    lsqr_size*: proc(a0: pointer): csize_t {.cdecl.}
    lsqr_ctx*: pointer

  struct_lsquic_ext_http_prio* {.pure, inheritable, bycopy.} = object
    urgency*: uint8
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1953:8
    incremental*: cschar

  struct_lsquic_logger_if* {.pure, inheritable, bycopy.} = object
    log_buf*: proc(a0: pointer, a1: cstring, a2: csize_t): cint {.cdecl.}
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:2026:8

  struct_lsquic_conn_info* {.pure, inheritable, bycopy.} = object
    lci_cwnd*: uint32
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:2250:8
    lci_pmtu*: uint32
    lci_rtt*: uint32
    lci_rttvar*: uint32
    lci_rtt_min*: uint32
    lci_bytes_rcvd*: uint64
    lci_bytes_sent*: uint64
    lci_pkts_rcvd*: uint64
    lci_pkts_sent*: uint64
    lci_pkts_lost*: uint64
    lci_pkts_retx*: uint64
    lci_bw_estimate*: uint64
    lci_max_pacing_rate*: uint64
    lci_pacing_rate*: uint64

  compiler_ssize_t* = clong
    ## Generated based on /usr/include/x86_64-linux-gnu/bits/types.h:194:27
  compiler_time_t* = clong
    ## Generated based on /usr/include/x86_64-linux-gnu/bits/types.h:160:26

when buf is typedesc:
  type idbuf* = buf
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic_types.h:30:9

else:
  when buf is static:
    const idbuf* = buf
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic_types.h:30:9
  else:
    let idbuf* = buf
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic_types.h:30:9
when 4 is static:
  const LSQUIC_MAJOR_VERSION* = 4
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:28:9
else:
  let LSQUIC_MAJOR_VERSION* = 4
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:28:9
when 10 is static:
  const LSQUIC_MINOR_VERSION* = 10
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:29:9
else:
  let LSQUIC_MINOR_VERSION* = 10
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:29:9
when 0 is static:
  const LSQUIC_PATCH_VERSION* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:30:9
else:
  let LSQUIC_PATCH_VERSION* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:30:9
when 100 is static:
  const LSQUIC_DF_MAX_STREAMS_IN* = 100
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:291:9
else:
  let LSQUIC_DF_MAX_STREAMS_IN* = 100
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:291:9
when LSQUIC_DF_CFCW_SERVER is typedesc:
  type LSQUIC_DF_INIT_MAX_DATA_SERVER* = LSQUIC_DF_CFCW_SERVER
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:294:9

else:
  when LSQUIC_DF_CFCW_SERVER is static:
    const LSQUIC_DF_INIT_MAX_DATA_SERVER* = LSQUIC_DF_CFCW_SERVER
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:294:9
  else:
    let LSQUIC_DF_INIT_MAX_DATA_SERVER* = LSQUIC_DF_CFCW_SERVER
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:294:9
when LSQUIC_DF_CFCW_CLIENT is typedesc:
  type LSQUIC_DF_INIT_MAX_DATA_CLIENT* = LSQUIC_DF_CFCW_CLIENT
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:295:9

else:
  when LSQUIC_DF_CFCW_CLIENT is static:
    const LSQUIC_DF_INIT_MAX_DATA_CLIENT* = LSQUIC_DF_CFCW_CLIENT
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:295:9
  else:
    let LSQUIC_DF_INIT_MAX_DATA_CLIENT* = LSQUIC_DF_CFCW_CLIENT
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:295:9
when LSQUIC_DF_SFCW_SERVER is typedesc:
  type LSQUIC_DF_INIT_MAX_STREAM_DATA_BIDI_REMOTE_SERVER* = LSQUIC_DF_SFCW_SERVER
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:296:9

else:
  when LSQUIC_DF_SFCW_SERVER is static:
    const LSQUIC_DF_INIT_MAX_STREAM_DATA_BIDI_REMOTE_SERVER* = LSQUIC_DF_SFCW_SERVER
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:296:9
  else:
    let LSQUIC_DF_INIT_MAX_STREAM_DATA_BIDI_REMOTE_SERVER* = LSQUIC_DF_SFCW_SERVER
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:296:9
when 0 is static:
  const LSQUIC_DF_INIT_MAX_STREAM_DATA_BIDI_LOCAL_SERVER* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:297:9
else:
  let LSQUIC_DF_INIT_MAX_STREAM_DATA_BIDI_LOCAL_SERVER* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:297:9
when 0 is static:
  const LSQUIC_DF_INIT_MAX_STREAM_DATA_BIDI_REMOTE_CLIENT* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:298:9
else:
  let LSQUIC_DF_INIT_MAX_STREAM_DATA_BIDI_REMOTE_CLIENT* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:298:9
when LSQUIC_DF_SFCW_CLIENT is typedesc:
  type LSQUIC_DF_INIT_MAX_STREAM_DATA_BIDI_LOCAL_CLIENT* = LSQUIC_DF_SFCW_CLIENT
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:299:9

else:
  when LSQUIC_DF_SFCW_CLIENT is static:
    const LSQUIC_DF_INIT_MAX_STREAM_DATA_BIDI_LOCAL_CLIENT* = LSQUIC_DF_SFCW_CLIENT
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:299:9
  else:
    let LSQUIC_DF_INIT_MAX_STREAM_DATA_BIDI_LOCAL_CLIENT* = LSQUIC_DF_SFCW_CLIENT
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:299:9
when LSQUIC_DF_MAX_STREAMS_IN is typedesc:
  type LSQUIC_DF_INIT_MAX_STREAMS_BIDI* = LSQUIC_DF_MAX_STREAMS_IN
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:300:9

else:
  when LSQUIC_DF_MAX_STREAMS_IN is static:
    const LSQUIC_DF_INIT_MAX_STREAMS_BIDI* = LSQUIC_DF_MAX_STREAMS_IN
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:300:9
  else:
    let LSQUIC_DF_INIT_MAX_STREAMS_BIDI* = LSQUIC_DF_MAX_STREAMS_IN
      ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:300:9
when 100 is static:
  const LSQUIC_DF_INIT_MAX_STREAMS_UNI_CLIENT* = 100
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:301:9
else:
  let LSQUIC_DF_INIT_MAX_STREAMS_UNI_CLIENT* = 100
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:301:9
when 3 is static:
  const LSQUIC_DF_INIT_MAX_STREAMS_UNI_SERVER* = 3
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:302:9
else:
  let LSQUIC_DF_INIT_MAX_STREAMS_UNI_SERVER* = 3
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:302:9
when 30 is static:
  const LSQUIC_DF_IDLE_TIMEOUT* = 30
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:310:9
else:
  let LSQUIC_DF_IDLE_TIMEOUT* = 30
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:310:9
when 15 is static:
  const LSQUIC_DF_PING_PERIOD* = 15
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:315:9
else:
  let LSQUIC_DF_PING_PERIOD* = 15
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:315:9
when 1 is static:
  const LSQUIC_DF_SILENT_CLOSE* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:323:9
else:
  let LSQUIC_DF_SILENT_CLOSE* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:323:9
when 0 is static:
  const LSQUIC_DF_MAX_HEADER_LIST_SIZE* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:329:9
else:
  let LSQUIC_DF_MAX_HEADER_LIST_SIZE* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:329:9
when 1 is static:
  const LSQUIC_DF_MAX_HEADER_SETS_SERVER* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:334:9
else:
  let LSQUIC_DF_MAX_HEADER_SETS_SERVER* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:334:9
when 2 is static:
  const LSQUIC_DF_MAX_HEADER_SETS_CLIENT* = 2
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:339:9
else:
  let LSQUIC_DF_MAX_HEADER_SETS_CLIENT* = 2
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:339:9
when "LSQUIC" is static:
  const LSQUIC_DF_UA* = "LSQUIC"
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:342:9
else:
  let LSQUIC_DF_UA* = "LSQUIC"
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:342:9
when 86400 is static:
  const LSQUIC_DF_STTL* = 86400
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:344:9
else:
  let LSQUIC_DF_STTL* = 86400
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:344:9
when 20 is static:
  const LSQUIC_DF_MAX_CRYPTO_STASH* = 20
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:347:9
else:
  let LSQUIC_DF_MAX_CRYPTO_STASH* = 20
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:347:9
when 1 is static:
  const LSQUIC_DF_SUPPORT_SREJ_SERVER* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:348:9
else:
  let LSQUIC_DF_SUPPORT_SREJ_SERVER* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:348:9
when 0 is static:
  const LSQUIC_DF_SUPPORT_SREJ_CLIENT* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:349:9
else:
  let LSQUIC_DF_SUPPORT_SREJ_CLIENT* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:349:9
when 0 is static:
  const LSQUIC_DF_SUPPORT_NSTP* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:352:9
else:
  let LSQUIC_DF_SUPPORT_NSTP* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:352:9
when 0 is static:
  const LSQUIC_DF_SUPPORT_PUSH* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:354:9
else:
  let LSQUIC_DF_SUPPORT_PUSH* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:354:9
when 1 is static:
  const LSQUIC_DF_SUPPORT_TCID0* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:355:9
else:
  let LSQUIC_DF_SUPPORT_TCID0* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:355:9
when 0 is static:
  const LSQUIC_DF_HONOR_PRST* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:357:9
else:
  let LSQUIC_DF_HONOR_PRST* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:357:9
when 0 is static:
  const LSQUIC_DF_SEND_PRST* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:363:9
else:
  let LSQUIC_DF_SEND_PRST* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:363:9
when 1 is static:
  const LSQUIC_DF_SEND_VERNEG* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:369:9
else:
  let LSQUIC_DF_SEND_VERNEG* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:369:9
when 1000 is static:
  const LSQUIC_DF_PROGRESS_CHECK* = 1000
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:372:9
else:
  let LSQUIC_DF_PROGRESS_CHECK* = 1000
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:372:9
when 0 is static:
  const LSQUIC_DF_RW_ONCE* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:375:9
else:
  let LSQUIC_DF_RW_ONCE* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:375:9
when 0 is static:
  const LSQUIC_DF_PROC_TIME_THRESH* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:378:9
else:
  let LSQUIC_DF_PROC_TIME_THRESH* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:378:9
when 1 is static:
  const LSQUIC_DF_PACE_PACKETS* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:381:9
else:
  let LSQUIC_DF_PACE_PACKETS* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:381:9
when 1000 is static:
  const LSQUIC_DF_CLOCK_GRANULARITY* = 1000
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:384:9
else:
  let LSQUIC_DF_CLOCK_GRANULARITY* = 1000
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:384:9
when 8 is static:
  const LSQUIC_DF_SCID_LEN* = 8
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:387:9
else:
  let LSQUIC_DF_SCID_LEN* = 8
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:387:9
when 60 is static:
  const LSQUIC_DF_SCID_ISS_RATE* = 60
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:390:9
else:
  let LSQUIC_DF_SCID_ISS_RATE* = 60
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:390:9
when 100 is static:
  const LSQUIC_DF_QPACK_DEC_MAX_BLOCKED* = 100
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:392:9
else:
  let LSQUIC_DF_QPACK_DEC_MAX_BLOCKED* = 100
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:392:9
when 4096 is static:
  const LSQUIC_DF_QPACK_DEC_MAX_SIZE* = 4096
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:393:9
else:
  let LSQUIC_DF_QPACK_DEC_MAX_SIZE* = 4096
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:393:9
when 100 is static:
  const LSQUIC_DF_QPACK_ENC_MAX_BLOCKED* = 100
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:394:9
else:
  let LSQUIC_DF_QPACK_ENC_MAX_BLOCKED* = 100
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:394:9
when 4096 is static:
  const LSQUIC_DF_QPACK_ENC_MAX_SIZE* = 4096
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:395:9
else:
  let LSQUIC_DF_QPACK_ENC_MAX_SIZE* = 4096
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:395:9
when 0 is static:
  const LSQUIC_DF_QPACK_EXPERIMENT* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:398:9
else:
  let LSQUIC_DF_QPACK_EXPERIMENT* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:398:9
when 0 is static:
  const LSQUIC_DF_ECN* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:401:9
else:
  let LSQUIC_DF_ECN* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:401:9
when 1 is static:
  const LSQUIC_DF_ALLOW_MIGRATION* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:404:9
else:
  let LSQUIC_DF_ALLOW_MIGRATION* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:404:9
when 10 is static:
  const LSQUIC_DF_RETRY_TOKEN_DURATION* = 10
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:407:9
else:
  let LSQUIC_DF_RETRY_TOKEN_DURATION* = 10
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:407:9
when 2 is static:
  const LSQUIC_DF_QL_BITS* = 2
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:410:9
else:
  let LSQUIC_DF_QL_BITS* = 2
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:410:9
when 1 is static:
  const LSQUIC_DF_SPIN* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:413:9
else:
  let LSQUIC_DF_SPIN* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:413:9
when 1 is static:
  const LSQUIC_DF_DELAYED_ACKS* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:416:9
else:
  let LSQUIC_DF_DELAYED_ACKS* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:416:9
when 3 is static:
  const LSQUIC_DF_PTPC_PERIODICITY* = 3
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:422:9
else:
  let LSQUIC_DF_PTPC_PERIODICITY* = 3
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:422:9
when 150 is static:
  const LSQUIC_DF_PTPC_MAX_PACKTOL* = 150
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:423:9
else:
  let LSQUIC_DF_PTPC_MAX_PACKTOL* = 150
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:423:9
when 1 is static:
  const LSQUIC_DF_PTPC_DYN_TARGET* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:424:9
else:
  let LSQUIC_DF_PTPC_DYN_TARGET* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:424:9
when 1.0 is static:
  const LSQUIC_DF_PTPC_TARGET* = 1.0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:425:9
else:
  let LSQUIC_DF_PTPC_TARGET* = 1.0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:425:9
when 0.8 is static:
  const LSQUIC_DF_PTPC_PROP_GAIN* = 0.8
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:426:9
else:
  let LSQUIC_DF_PTPC_PROP_GAIN* = 0.8
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:426:9
when 0.35 is static:
  const LSQUIC_DF_PTPC_INT_GAIN* = 0.35
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:427:9
else:
  let LSQUIC_DF_PTPC_INT_GAIN* = 0.35
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:427:9
when 0.05 is static:
  const LSQUIC_DF_PTPC_ERR_THRESH* = 0.05
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:428:9
else:
  let LSQUIC_DF_PTPC_ERR_THRESH* = 0.05
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:428:9
when 0.05 is static:
  const LSQUIC_DF_PTPC_ERR_DIVISOR* = 0.05
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:429:9
else:
  let LSQUIC_DF_PTPC_ERR_DIVISOR* = 0.05
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:429:9
when 1 is static:
  const LSQUIC_DF_TIMESTAMPS* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:432:9
else:
  let LSQUIC_DF_TIMESTAMPS* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:432:9
when 3 is static:
  const LSQUIC_DF_AMP_FACTOR* = 3
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:435:9
else:
  let LSQUIC_DF_AMP_FACTOR* = 3
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:435:9
when 3 is static:
  const LSQUIC_DF_CC_ALGO* = 3
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:438:9
else:
  let LSQUIC_DF_CC_ALGO* = 3
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:438:9
when 1500 is static:
  const LSQUIC_DF_CC_RTT_THRESH* = 1500
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:441:9
else:
  let LSQUIC_DF_CC_RTT_THRESH* = 1500
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:441:9
when 0 is static:
  const LSQUIC_DF_ENABLE_BW_SAMPLER* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:444:9
else:
  let LSQUIC_DF_ENABLE_BW_SAMPLER* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:444:9
when 0 is static:
  const LSQUIC_DF_DATAGRAMS* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:447:9
else:
  let LSQUIC_DF_DATAGRAMS* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:447:9
when 1 is static:
  const LSQUIC_DF_OPTIMISTIC_NAT* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:450:9
else:
  let LSQUIC_DF_OPTIMISTIC_NAT* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:450:9
when 1 is static:
  const LSQUIC_DF_EXT_HTTP_PRIO* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:453:9
else:
  let LSQUIC_DF_EXT_HTTP_PRIO* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:453:9
when 0 is static:
  const LSQUIC_DF_MAX_UDP_PAYLOAD_SIZE_RX* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:456:9
else:
  let LSQUIC_DF_MAX_UDP_PAYLOAD_SIZE_RX* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:456:9
when 1 is static:
  const LSQUIC_DF_GREASE_QUIC_BIT* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:462:9
else:
  let LSQUIC_DF_GREASE_QUIC_BIT* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:462:9
when 1 is static:
  const LSQUIC_DF_DPLPMTUD* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:465:9
else:
  let LSQUIC_DF_DPLPMTUD* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:465:9
when 0 is static:
  const LSQUIC_DF_BASE_PLPMTU* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:468:9
else:
  let LSQUIC_DF_BASE_PLPMTU* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:468:9
when 0 is static:
  const LSQUIC_DF_MAX_PLPMTU* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:471:9
else:
  let LSQUIC_DF_MAX_PLPMTU* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:471:9
when 60 is static:
  const LSQUIC_DF_NOPROGRESS_TIMEOUT_SERVER* = 60
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:474:9
else:
  let LSQUIC_DF_NOPROGRESS_TIMEOUT_SERVER* = 60
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:474:9
when 0 is static:
  const LSQUIC_DF_NOPROGRESS_TIMEOUT_CLIENT* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:477:9
else:
  let LSQUIC_DF_NOPROGRESS_TIMEOUT_CLIENT* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:477:9
when 1000 is static:
  const LSQUIC_DF_MTU_PROBE_TIMER* = 1000
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:480:9
else:
  let LSQUIC_DF_MTU_PROBE_TIMER* = 1000
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:480:9
when 0 is static:
  const LSQUIC_DF_DELAY_ONCLOSE* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:483:9
else:
  let LSQUIC_DF_DELAY_ONCLOSE* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:483:9
when 0 is static:
  const LSQUIC_DF_MAX_BATCH_SIZE* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:489:9
else:
  let LSQUIC_DF_MAX_BATCH_SIZE* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:489:9
when 32 is static:
  const LSQUIC_DF_MAX_DELAYED_0RTT_PACKETS* = 32
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:492:9
else:
  let LSQUIC_DF_MAX_DELAYED_0RTT_PACKETS* = 32
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:492:9
when 1 is static:
  const LSQUIC_DF_CHECK_TP_SANITY* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:495:9
else:
  let LSQUIC_DF_CHECK_TP_SANITY* = 1
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:495:9
when 7 is static:
  const LSQUIC_MAX_HTTP_URGENCY* = 7
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1949:9
else:
  let LSQUIC_MAX_HTTP_URGENCY* = 7
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1949:9
when 3 is static:
  const LSQUIC_DEF_HTTP_URGENCY* = 3
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1950:9
else:
  let LSQUIC_DEF_HTTP_URGENCY* = 3
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1950:9
when 0 is static:
  const LSQUIC_DEF_HTTP_INCREMENTAL* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1951:9
else:
  let LSQUIC_DEF_HTTP_INCREMENTAL* = 0
    ## Generated based on /home/r/vacp2p/nim-lsquic/libs/lsquic/include/lsquic.h:1951:9
proc lsquic_engine_init_settings*(
  a0: ptr struct_lsquic_engine_settings, lsquic_engine_flags: cuint
): void {.cdecl, importc: "lsquic_engine_init_settings".}

proc lsquic_engine_check_settings*(
  settings: ptr struct_lsquic_engine_settings,
  lsquic_engine_flags: cuint,
  err_buf: cstring,
  err_buf_sz: csize_t,
): cint {.cdecl, importc: "lsquic_engine_check_settings".}

proc lsquic_engine_get_conns_count*(
  engine: ptr lsquic_engine_t
): cuint {.cdecl, importc: "lsquic_engine_get_conns_count".}

proc lsquic_engine_new*(
  lsquic_engine_flags: cuint, api: ptr struct_lsquic_engine_api
): ptr lsquic_engine_t {.cdecl, importc: "lsquic_engine_new".}

proc lsquic_engine_connect*(
  a0: ptr lsquic_engine_t,
  a1: enum_lsquic_version,
  local_sa: ptr SockAddr,
  peer_sa: ptr SockAddr,
  peer_ctx: pointer,
  conn_ctx: ptr lsquic_conn_ctx_t,
  hostname: cstring,
  base_plpmtu: cushort,
  sess_resume: ptr uint8,
  sess_resume_len: csize_t,
  token: ptr uint8,
  token_sz: csize_t,
): ptr lsquic_conn_t {.cdecl, importc: "lsquic_engine_connect".}

proc lsquic_engine_packet_in*(
  a0: ptr lsquic_engine_t,
  packet_in_data: ptr uint8,
  packet_in_size: csize_t,
  sa_local: ptr SockAddr,
  sa_peer: ptr SockAddr,
  peer_ctx: pointer,
  ecn: cint,
): cint {.cdecl, importc: "lsquic_engine_packet_in".}

proc lsquic_engine_process_conns*(
  engine: ptr lsquic_engine_t
): void {.cdecl, importc: "lsquic_engine_process_conns".}

proc lsquic_engine_has_unsent_packets*(
  engine: ptr lsquic_engine_t
): cint {.cdecl, importc: "lsquic_engine_has_unsent_packets".}

proc lsquic_engine_send_unsent_packets*(
  engine: ptr lsquic_engine_t
): void {.cdecl, importc: "lsquic_engine_send_unsent_packets".}

proc lsquic_engine_destroy*(
  a0: ptr lsquic_engine_t
): void {.cdecl, importc: "lsquic_engine_destroy".}

proc lsquic_conn_n_avail_streams*(
  a0: ptr lsquic_conn_t
): cuint {.cdecl, importc: "lsquic_conn_n_avail_streams".}

proc lsquic_conn_make_stream*(
  a0: ptr lsquic_conn_t
): void {.cdecl, importc: "lsquic_conn_make_stream".}

proc lsquic_conn_n_pending_streams*(
  a0: ptr lsquic_conn_t
): cuint {.cdecl, importc: "lsquic_conn_n_pending_streams".}

proc lsquic_conn_cancel_pending_streams*(
  a0: ptr lsquic_conn_t, n: cuint
): cuint {.cdecl, importc: "lsquic_conn_cancel_pending_streams".}

proc lsquic_conn_going_away*(
  a0: ptr lsquic_conn_t
): void {.cdecl, importc: "lsquic_conn_going_away".}

proc lsquic_conn_close*(
  a0: ptr lsquic_conn_t
): void {.cdecl, importc: "lsquic_conn_close".}

proc lsquic_stream_wantread*(
  s: ptr lsquic_stream_t, is_want: cint
): cint {.cdecl, importc: "lsquic_stream_wantread".}

proc lsquic_stream_read*(
  s: ptr lsquic_stream_t, buf: pointer, len: csize_t
): ssize_t {.cdecl, importc: "lsquic_stream_read".}

proc lsquic_stream_readv*(
  s: ptr lsquic_stream_t, vec: ptr struct_iovec, iovcnt: cint
): ssize_t {.cdecl, importc: "lsquic_stream_readv".}

proc lsquic_stream_readf*(
  s: ptr lsquic_stream_t,
  readf: proc(a0: pointer, a1: ptr uint8, a2: csize_t, a3: cint): csize_t {.cdecl.},
  ctx: pointer,
): ssize_t {.cdecl, importc: "lsquic_stream_readf".}

proc lsquic_stream_wantwrite*(
  s: ptr lsquic_stream_t, is_want: cint
): cint {.cdecl, importc: "lsquic_stream_wantwrite".}

proc lsquic_stream_write*(
  s: ptr lsquic_stream_t, buf: pointer, len: csize_t
): ssize_t {.cdecl, importc: "lsquic_stream_write".}

proc lsquic_stream_writev*(
  s: ptr lsquic_stream_t, vec: ptr struct_iovec, count: cint
): ssize_t {.cdecl, importc: "lsquic_stream_writev".}

proc lsquic_stream_pwritev*(
  s: ptr lsquic_stream_t,
  preadv: proc(a0: pointer, a1: ptr struct_iovec, a2: cint): ssize_t {.cdecl.},
  user_data: pointer,
  n_to_write: csize_t,
): ssize_t {.cdecl, importc: "lsquic_stream_pwritev".}

proc lsquic_stream_writef*(
  a0: ptr lsquic_stream_t, a1: ptr struct_lsquic_reader
): ssize_t {.cdecl, importc: "lsquic_stream_writef".}

proc lsquic_stream_flush*(
  s: ptr lsquic_stream_t
): cint {.cdecl, importc: "lsquic_stream_flush".}

proc lsquic_stream_send_headers*(
  s: ptr lsquic_stream_t, headers: ptr lsquic_http_headers_t, eos: cint
): cint {.cdecl, importc: "lsquic_stream_send_headers".}

proc lsquic_stream_get_hset*(
  a0: ptr lsquic_stream_t
): pointer {.cdecl, importc: "lsquic_stream_get_hset".}

proc lsquic_conn_push_stream*(
  c: ptr lsquic_conn_t,
  hdr_set: pointer,
  s: ptr lsquic_stream_t,
  headers: ptr lsquic_http_headers_t,
): cint {.cdecl, importc: "lsquic_conn_push_stream".}

proc lsquic_conn_is_push_enabled*(
  a0: ptr lsquic_conn_t
): cint {.cdecl, importc: "lsquic_conn_is_push_enabled".}

proc lsquic_stream_shutdown*(
  s: ptr lsquic_stream_t, how: cint
): cint {.cdecl, importc: "lsquic_stream_shutdown".}

proc lsquic_stream_close*(
  s: ptr lsquic_stream_t
): cint {.cdecl, importc: "lsquic_stream_close".}

proc lsquic_stream_has_unacked_data*(
  s: ptr lsquic_stream_t
): cint {.cdecl, importc: "lsquic_stream_has_unacked_data".}

proc lsquic_conn_get_server_cert_chain*(
  a0: ptr lsquic_conn_t
): ptr struct_stack_st_X509 {.cdecl, importc: "lsquic_conn_get_server_cert_chain".}

proc lsquic_conn_get_full_peer_cert_chain*(
  a0: ptr lsquic_conn_t
): ptr struct_stack_st_X509 {.cdecl, importc: "lsquic_conn_get_full_peer_cert_chain".}

proc lsquic_conn_get_full_cert_chain*(
  a0: ptr lsquic_conn_t
): ptr struct_stack_st_X509 {.cdecl, importc: "lsquic_conn_get_full_cert_chain".}

proc lsquic_stream_id*(
  s: ptr lsquic_stream_t
): lsquic_stream_id_t {.cdecl, importc: "lsquic_stream_id".}

proc lsquic_stream_get_ctx*(
  s: ptr lsquic_stream_t
): ptr lsquic_stream_ctx_t {.cdecl, importc: "lsquic_stream_get_ctx".}

proc lsquic_stream_set_ctx*(
  stream: ptr lsquic_stream_t, ctx: ptr lsquic_stream_ctx_t
): void {.cdecl, importc: "lsquic_stream_set_ctx".}

proc lsquic_stream_is_pushed*(
  s: ptr lsquic_stream_t
): cint {.cdecl, importc: "lsquic_stream_is_pushed".}

proc lsquic_stream_is_rejected*(
  s: ptr lsquic_stream_t
): cint {.cdecl, importc: "lsquic_stream_is_rejected".}

proc lsquic_stream_refuse_push*(
  s: ptr lsquic_stream_t
): cint {.cdecl, importc: "lsquic_stream_refuse_push".}

proc lsquic_stream_push_info*(
  a0: ptr lsquic_stream_t, ref_stream_id: ptr lsquic_stream_id_t, hdr_set: ptr pointer
): cint {.cdecl, importc: "lsquic_stream_push_info".}

proc lsquic_stream_priority*(
  s: ptr lsquic_stream_t
): cuint {.cdecl, importc: "lsquic_stream_priority".}

proc lsquic_stream_set_priority*(
  s: ptr lsquic_stream_t, priority: cuint
): cint {.cdecl, importc: "lsquic_stream_set_priority".}

proc lsquic_stream_get_http_prio*(
  a0: ptr lsquic_stream_t, a1: ptr struct_lsquic_ext_http_prio
): cint {.cdecl, importc: "lsquic_stream_get_http_prio".}

proc lsquic_stream_set_http_prio*(
  a0: ptr lsquic_stream_t, a1: ptr struct_lsquic_ext_http_prio
): cint {.cdecl, importc: "lsquic_stream_set_http_prio".}

proc lsquic_stream_conn*(
  s: ptr lsquic_stream_t
): ptr lsquic_conn_t {.cdecl, importc: "lsquic_stream_conn".}

proc lsquic_conn_id*(
  c: ptr lsquic_conn_t
): ptr lsquic_cid_t {.cdecl, importc: "lsquic_conn_id".}

proc lsquic_conn_get_engine*(
  c: ptr lsquic_conn_t
): ptr lsquic_engine_t {.cdecl, importc: "lsquic_conn_get_engine".}

proc lsquic_conn_get_sockaddr*(
  c: ptr lsquic_conn_t, local: ptr ptr SockAddr, peer: ptr ptr SockAddr
): cint {.cdecl, importc: "lsquic_conn_get_sockaddr".}

proc lsquic_conn_want_datagram_write*(
  a0: ptr lsquic_conn_t, is_want: cint
): cint {.cdecl, importc: "lsquic_conn_want_datagram_write".}

proc lsquic_conn_get_min_datagram_size*(
  a0: ptr lsquic_conn_t
): csize_t {.cdecl, importc: "lsquic_conn_get_min_datagram_size".}

proc lsquic_conn_set_min_datagram_size*(
  a0: ptr lsquic_conn_t, sz: csize_t
): cint {.cdecl, importc: "lsquic_conn_set_min_datagram_size".}

proc lsquic_logger_init*(
  a0: ptr struct_lsquic_logger_if,
  logger_ctx: pointer,
  a2: enum_lsquic_logger_timestamp_style,
): void {.cdecl, importc: "lsquic_logger_init".}

proc lsquic_set_log_level*(
  log_level: cstring
): cint {.cdecl, importc: "lsquic_set_log_level".}

proc lsquic_logger_lopt*(optarg: cstring): cint {.cdecl, importc: "lsquic_logger_lopt".}
proc lsquic_engine_quic_versions*(
  a0: ptr lsquic_engine_t
): cuint {.cdecl, importc: "lsquic_engine_quic_versions".}

proc lsquic_global_init*(flags: cint): cint {.cdecl, importc: "lsquic_global_init".}
proc lsquic_global_cleanup*(): void {.cdecl, importc: "lsquic_global_cleanup".}
proc lsquic_conn_quic_version*(
  c: ptr lsquic_conn_t
): enum_lsquic_version {.cdecl, importc: "lsquic_conn_quic_version".}

proc lsquic_conn_crypto_keysize*(
  c: ptr lsquic_conn_t
): cint {.cdecl, importc: "lsquic_conn_crypto_keysize".}

proc lsquic_conn_crypto_alg_keysize*(
  c: ptr lsquic_conn_t
): cint {.cdecl, importc: "lsquic_conn_crypto_alg_keysize".}

proc lsquic_conn_crypto_ver*(
  c: ptr lsquic_conn_t
): enum_lsquic_crypto_ver {.cdecl, importc: "lsquic_conn_crypto_ver".}

proc lsquic_conn_crypto_cipher*(
  c: ptr lsquic_conn_t
): cstring {.cdecl, importc: "lsquic_conn_crypto_cipher".}

proc lsquic_str2ver*(
  str: cstring, len: csize_t
): enum_lsquic_version {.cdecl, importc: "lsquic_str2ver".}

proc lsquic_alpn2ver*(
  alpn: cstring, len: csize_t
): enum_lsquic_version {.cdecl, importc: "lsquic_alpn2ver".}

proc lsquic_engine_cooldown*(
  a0: ptr lsquic_engine_t
): void {.cdecl, importc: "lsquic_engine_cooldown".}

proc lsquic_conn_get_ctx*(
  a0: ptr lsquic_conn_t
): ptr lsquic_conn_ctx_t {.cdecl, importc: "lsquic_conn_get_ctx".}

proc lsquic_conn_set_ctx*(
  a0: ptr lsquic_conn_t, a1: ptr lsquic_conn_ctx_t
): void {.cdecl, importc: "lsquic_conn_set_ctx".}

proc lsquic_conn_get_peer_ctx*(
  a0: ptr lsquic_conn_t, local_sa: ptr SockAddr
): pointer {.cdecl, importc: "lsquic_conn_get_peer_ctx".}

proc lsquic_conn_get_sni*(
  a0: ptr lsquic_conn_t
): cstring {.cdecl, importc: "lsquic_conn_get_sni".}

proc lsquic_conn_abort*(
  a0: ptr lsquic_conn_t
): void {.cdecl, importc: "lsquic_conn_abort".}

proc lsquic_conn_get_info*(
  conn: ptr lsquic_conn_t, info: ptr struct_lsquic_conn_info
): cint {.cdecl, importc: "lsquic_conn_get_info".}

proc lsquic_conn_set_param*(
  conn: ptr lsquic_conn_t,
  param: enum_lsquic_conn_param,
  value: pointer,
  value_len: csize_t,
): cint {.cdecl, importc: "lsquic_conn_set_param".}

proc lsquic_conn_get_param*(
  conn: ptr lsquic_conn_t,
  param: enum_lsquic_conn_param,
  value: pointer,
  value_len: ptr csize_t,
): cint {.cdecl, importc: "lsquic_conn_get_param".}

proc lsquic_get_alt_svc_versions*(
  versions: cuint
): cstring {.cdecl, importc: "lsquic_get_alt_svc_versions".}

proc lsquic_get_h3_alpns*(
  versions: cuint
): ptr cstring {.cdecl, importc: "lsquic_get_h3_alpns".}

proc lsquic_is_valid_hs_packet*(
  a0: ptr lsquic_engine_t, a1: ptr uint8, a2: csize_t
): cint {.cdecl, importc: "lsquic_is_valid_hs_packet".}

proc lsquic_cid_from_packet*(
  a0: ptr uint8, bufsz: csize_t, cid: ptr lsquic_cid_t
): cint {.cdecl, importc: "lsquic_cid_from_packet".}

proc lsquic_dcid_from_packet*(
  a0: ptr uint8, bufsz: csize_t, server_cid_len: cuint, cid_len: ptr uint8
): cint {.cdecl, importc: "lsquic_dcid_from_packet".}

proc lsquic_engine_earliest_adv_tick*(
  engine: ptr lsquic_engine_t, diff: ptr cint
): cint {.cdecl, importc: "lsquic_engine_earliest_adv_tick".}

proc lsquic_engine_count_attq*(
  engine: ptr lsquic_engine_t, from_now: cint
): cuint {.cdecl, importc: "lsquic_engine_count_attq".}

proc lsquic_conn_status*(
  a0: ptr lsquic_conn_t, errbuf: cstring, bufsz: csize_t
): enum_LSQUIC_CONN_STATUS {.cdecl, importc: "lsquic_conn_status".}

var lsquic_ver2str* {.importc: "lsquic_ver2str".}: array[8'i64, cstring]
proc lsquic_ssl_to_conn*(
  a0: ptr struct_ssl_st
): ptr lsquic_conn_t {.cdecl, importc: "lsquic_ssl_to_conn".}

proc lsquic_ssl_sess_to_resume_info*(
  a0: ptr struct_ssl_st,
  a1: ptr struct_ssl_session_st,
  buf: ptr ptr uint8,
  buf_sz: ptr csize_t,
): cint {.cdecl, importc: "lsquic_ssl_sess_to_resume_info".}

# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH 

const
  LSQUIC_GLOBAL_CLIENT* = (1 shl 0)
  LSQUIC_GLOBAL_SERVER* = (1 shl 1)

# Engine modes
const
  LSENG_SERVER* = (1 shl 0)
  LSENG_HTTP* = (1 shl 1)
  LSENG_HTTP_SERVER* = (LSENG_SERVER or LSENG_HTTP)
