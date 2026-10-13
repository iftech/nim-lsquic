# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH 

import std/os
import chronicles
import lsquic_ffi

proc nativeLog(
    ctx: pointer, buf: cstring, len: csize_t
): cint {.cdecl, gcsafe, raises: [].} =
  # LSQUIC supplies a length-delimited buffer that is valid only during this call.
  var message = newString(len.int)
  if len > 0:
    copyMem(addr message[0], buf, len.int)
  while message.len > 0 and message[^1] in {'\r', '\n'}:
    message.setLen(message.len - 1)
  debug "LSQUIC native", topics = "lsquic_native", message = message
  len.cint

var
  initialized: bool
  nativeLogger = struct_lsquic_logger_if(log_buf: nativeLog)

proc configureNativeLogging() =
  let options = getEnv("NIM_LSQUIC_LOG")
  if options.len == 0:
    return
  if lsquic_logger_lopt(options.cstring) != 0:
    raise newException(ValueError, "invalid NIM_LSQUIC_LOG: " & options)
  lsquic_logger_init(addr nativeLogger, nil, LLTS_NONE)
  info "LSQUIC native logging enabled", topics = "lsquic", modules = options

proc initializeLsquic*(client: bool = true, server: bool = true) =
  if initialized:
    return
  configureNativeLogging()
  var flags = 0.cint
  if client:
    flags = flags or LSQUIC_GLOBAL_CLIENT
  if server:
    flags = flags or LSQUIC_GLOBAL_SERVER

  if lsquic_global_init(flags) != 0:
    raiseAssert "lsquic initialization failed"
  initialized = true

proc cleanupLsquic*() =
  if not initialized:
    return
  lsquic_global_cleanup()
  initialized = false
