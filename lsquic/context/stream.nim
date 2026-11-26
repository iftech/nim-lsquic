# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH 

import std/[posix]
import chronicles
import chronos
import ../[lsquic_ffi, errors, stream, tracking]
import ../helpers/[logging, sequninit]

logScope:
  topics = "lsquic"

proc onReset*(
    stream: ptr lsquic_stream_t, ctx: ptr lsquic_stream_ctx_t, how: cint
) {.cdecl.} =
  let sHow =
    case how
    of 0: ResetRead
    of 1: ResetWrite
    of 2: ResetReadWrite
    else: ResetReadWrite
  trace "Peer reset stream", reset = $sHow
  if ctx.isNil:
    trace "Stream reset received without a stream context", reset = $sHow
    return

  let streamCtx = cast[Stream](ctx)

  streamCtx.markResetByPeer(sHow)

  if streamCtx.readResetByPeer():
    streamCtx.failPendingRead(streamCtx.newStreamResetError("stream read"))

  if streamCtx.writeResetByPeer():
    streamCtx.abortPendingWrites(streamCtx.newStreamResetError("stream write"))

  if not streamCtx.closeIfDone():
    streamCtx.abort()

proc onClose*(stream: ptr lsquic_stream_t, ctx: ptr lsquic_stream_ctx_t) {.cdecl.} =
  trace "Stream closed by QUIC engine"
  if ctx.isNil:
    trace "Stream close received without a stream context"
    return

  let streamCtx = cast[Stream](ctx)

  streamCtx.closedByEngine = true

  streamCtx.abortPendingWrites("stream closed")

  # Always signal closure so waiters are released, even if we already shut down
  # the write side locally.
  if not streamCtx.closed.isSet():
    streamCtx.closed.fire()

  if streamCtx.readResetByPeer():
    streamCtx.failPendingRead(streamCtx.newStreamResetError("stream read"))
  elif streamCtx.isEof:
    streamCtx.completePendingRead()
  else:
    streamCtx.markReadFailed("stream closed before end of stream")
    streamCtx.failPendingRead(newException(StreamError, streamCtx.readFailure))

  unpin(streamCtx)

proc onRead*(stream: ptr lsquic_stream_t, ctx: ptr lsquic_stream_ctx_t) {.cdecl.} =
  trace "Stream read callback received"
  if ctx.isNil:
    trace "Stream read callback received without a stream context"
    return

  let streamCtx = cast[Stream](ctx)

  let task = streamCtx.toRead.valueOr:
    if lsquic_stream_wantread(stream, 0) == -1:
      let readErrno = errno
      if readErrno != EBADF:
        trace "Failed to disable stream read notifications",
          streamId = lsquic_stream_id(stream), error = osErrorLabel(readErrno)
        streamCtx.abort()
    return

  var receivedFin = false
  let n = readFromStream(stream, task.data, task.dataLen, receivedFin)

  if n < 0:
    if errno == EWOULDBLOCK:
      # Try later
      return
    elif errno == ECONNRESET:
      if not streamCtx.readResetByPeer():
        streamCtx.markResetByPeer(ResetRead)
      streamCtx.failPendingRead(streamCtx.newStreamResetError("stream read"))
      return
    else:
      trace "Failed to read from stream",
        streamId = lsquic_stream_id(stream), error = osErrorLabel(errno)
      streamCtx.abort()
      return

  if receivedFin:
    streamCtx.isEof = true
  if n == 0 and streamCtx.isEof:
    if not streamCtx.closeIfDone():
      trace "Failed to close stream after receiving end of input",
        streamId = lsquic_stream_id(stream)
      streamCtx.failPendingRead(newException(StreamError, "could not close the stream"))
      streamCtx.abort()
      return

  # Report bytes before clearing the task. closeIfDone above may re-enter onClose.
  if not task.doneFut.finished:
    task.doneFut.complete(int(n))

  streamCtx.toRead = Opt.none(ReadTask)

  if lsquic_stream_wantread(stream, 0) == -1:
    let readErrno = errno
    if readErrno != EBADF:
      trace "Failed to disable stream read notifications",
        streamId = lsquic_stream_id(stream), error = osErrorLabel(readErrno)
      streamCtx.abort()

proc onWrite*(stream: ptr lsquic_stream_t, ctx: ptr lsquic_stream_ctx_t) {.cdecl.} =
  trace "Stream write callback received"

  if ctx.isNil:
    trace "Stream write callback received without a stream context"
    return

  let streamCtx = cast[Stream](ctx)

  var w = streamCtx.toWrite.valueOr:
    if lsquic_stream_wantwrite(stream, 0) == -1:
      let writeErrno = errno
      if writeErrno != EBADF:
        trace "Failed to disable stream write notifications",
          streamId = lsquic_stream_id(stream), error = osErrorLabel(writeErrno)
        streamCtx.abort()
    return

  let dataArr = cast[ptr UncheckedArray[byte]](w.data)
  while not w.doneFut.finished:
    let p = dataArr[w.offset].addr
    let nAvail = (w.dataLen - w.offset).csize_t
    let n: ssize_t = lsquic_stream_write(stream, p, nAvail)
    if n > 0:
      w.offset += n.int
      if w.offset >= w.dataLen:
        if not w.doneFut.finished:
          w.doneFut.complete()
    elif n == 0:
      # Nothing to write, try later
      break
    else:
      if errno == ECONNRESET:
        if not streamCtx.writeResetByPeer():
          streamCtx.markResetByPeer(ResetWrite)
        streamCtx.abortPendingWrites(streamCtx.newStreamResetError("stream write"))
        return
      streamCtx.abortPendingWrites("write failed")
      break

  if lsquic_stream_flush(stream) != 0:
    streamCtx.abort()
    return

  if not w.doneFut.finished:
    streamCtx.toWrite = Opt.some(w)
    return

  streamCtx.toWrite = Opt.none(WriteTask)

  if lsquic_stream_wantwrite(stream, 0) == -1:
    let writeErrno = errno
    if writeErrno != EBADF:
      trace "Failed to disable stream write notifications",
        streamId = lsquic_stream_id(stream), error = osErrorLabel(writeErrno)
      streamCtx.abort()
