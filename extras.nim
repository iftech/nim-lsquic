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

# Internal API of the bundled lsquic source: public close sends FIN, not reset.
proc lsquic_stream_maybe_reset*(
  s: ptr lsquic_stream_t, error_code: uint64, do_close: cint
) {.cdecl, importc: "lsquic_stream_maybe_reset".}
