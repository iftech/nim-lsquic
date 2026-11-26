# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH 

import std/[deques, posix]
import chronos
import chronicles
import ./[lsquic_ffi, errors, tracking]
import ./helpers/logging

logScope:
  topics = "lsquic"

const WriteFlushBytes = 16384
  ## Large writes flush immediately; smaller writes defer to coalesce ticks.

type WriteTask* = object
  data*: ptr byte
  dataLen*: int
  offset*: int
  doneFut*: Future[void].Raising([CancelledError, StreamError])

type ReadTask* = object
  data*: ptr byte
  dataLen*: int
  doneFut*: Future[int].Raising([CancelledError, StreamError])

type ReadContext = object
  data: ptr byte
  dataLen: int
  offset: int
  receivedFin: bool

type Stream* = ref object
  quicStream*: ptr lsquic_stream_t
  canRead*: bool
  canWrite*: bool
  closedByEngine*: bool
  closeWrite*: bool
  closeRequested: bool
  # This is called when on_close callback is executed
  closed*: AsyncEvent
  resetByPeer*: bool
  resetHow*: StreamResetHow
  writeLock*: AsyncLock
  toWrite*: Opt[WriteTask]
  readLock*: AsyncLock
  isEof*: bool # Received a FIN from remote
  readFailure*: string
  # Every path that sets closedByEngine or fires `closed` must settle these;
  # missing one hangs the parked operation instead of failing it.
  toRead*: Opt[ReadTask]
  doProcess*: proc(urgent: bool) {.gcsafe, raises: [].}

proc new*(
    T: typedesc[Stream],
    quicStream: ptr lsquic_stream_t = nil,
    canRead = true,
    canWrite = true,
): T =
  let closed = newAsyncEvent()
  let s = Stream(
    quicStream: quicStream,
    canRead: canRead,
    canWrite: canWrite,
    closeWrite: not canWrite,
    closed: closed,
    readLock: newAsyncLock(),
    writeLock: newAsyncLock(),
  )
  pin(s) # Keep it pinned until stream_if.on_close is executed
  s

proc readResetByPeer*(stream: Stream): bool {.raises: [].} =
  stream.resetByPeer and stream.resetHow in {ResetRead, ResetReadWrite}

proc writeResetByPeer*(stream: Stream): bool {.raises: [].} =
  stream.resetByPeer and stream.resetHow in {ResetWrite, ResetReadWrite}

proc markResetByPeer*(stream: Stream, how: StreamResetHow) {.raises: [].} =
  let mergedHow =
    if stream.resetByPeer and stream.resetHow != how: ResetReadWrite else: how

  stream.resetByPeer = true
  stream.resetHow = mergedHow

  if mergedHow in {ResetWrite, ResetReadWrite}:
    stream.closeWrite = true

proc newStreamResetError*(
    stream: Stream, operation: string
): ref StreamResetError {.raises: [].} =
  let exc = newException(
    StreamResetError, operation & " reset by peer (" & $stream.resetHow & ")"
  )
  exc.how = stream.resetHow
  exc

proc markReadFailed*(stream: Stream, reason: string) {.raises: [].} =
  if stream.readFailure.len == 0:
    stream.readFailure = reason

proc readToBuffer(
    ctx: pointer, data: ptr uint8, dataLen: csize_t, fin: cint
): csize_t {.cdecl, raises: [].} =
  let readCtx = cast[ptr ReadContext](ctx)
  let remaining = readCtx.dataLen - readCtx.offset
  let count = min(dataLen, remaining.csize_t).int
  if count > 0:
    let dst = cast[ptr UncheckedArray[byte]](readCtx.data)
    copyMem(addr dst[readCtx.offset], data, count)
    readCtx.offset += count
  if fin != 0 and count.csize_t == dataLen:
    readCtx.receivedFin = true
  count.csize_t

proc readFromStream*(
    stream: ptr lsquic_stream_t, data: ptr byte, dataLen: int, receivedFin: var bool
): ssize_t {.raises: [].} =
  receivedFin = false
  if dataLen < 0 or (dataLen > 0 and data.isNil):
    errno = EINVAL
    return -1

  var readCtx = ReadContext(data: data, dataLen: dataLen)
  let n = lsquic_stream_readf(stream, readToBuffer, addr readCtx)
  receivedFin = readCtx.receivedFin
  return n

proc failPendingRead*(stream: Stream, error: ref StreamError) {.raises: [].} =
  let task = stream.toRead.valueOr:
    return
  if not task.doneFut.finished:
    task.doneFut.fail(error)
  stream.toRead = Opt.none(ReadTask)

proc completePendingRead*(stream: Stream) {.raises: [].} =
  ## Ends a pending read at end of stream, reporting 0 rather than failing.
  let task = stream.toRead.valueOr:
    return
  if not task.doneFut.finished:
    task.doneFut.complete(0)
  stream.toRead = Opt.none(ReadTask)

proc abortPendingWrites*(stream: Stream, error: ref StreamError) {.raises: [].} =
  let task = stream.toWrite.valueOr:
    return
  if not task.doneFut.finished:
    task.doneFut.fail(error)
  stream.toWrite = Opt.none(WriteTask)

proc abortPendingWrites*(stream: Stream, reason: string = "") {.raises: [].} =
  stream.abortPendingWrites(newException(StreamError, reason))

proc clearPendingRead(
    stream: Stream, doneFut: Future[int].Raising([CancelledError, StreamError])
) {.raises: [].} =
  let task = stream.toRead.valueOr:
    return
  if task.doneFut != doneFut:
    return

  stream.toRead = Opt.none(ReadTask)

  if stream.closedByEngine or stream.quicStream.isNil:
    return

  if lsquic_stream_wantread(stream.quicStream, 0) == -1:
    let readErrno = errno
    if readErrno != EBADF:
      debug "Failed to disable stream read notifications",
        streamId = lsquic_stream_id(stream.quicStream), error = osErrorLabel(readErrno)

proc clearPendingWrite(
    stream: Stream, doneFut: Future[void].Raising([CancelledError, StreamError])
) {.raises: [].} =
  let task = stream.toWrite.valueOr:
    return
  if task.doneFut != doneFut:
    return

  stream.toWrite = Opt.none(WriteTask)

  if stream.closedByEngine or stream.quicStream.isNil:
    return

  if lsquic_stream_wantwrite(stream.quicStream, 0) == -1:
    let writeErrno = errno
    if writeErrno != EBADF:
      debug "Failed to disable stream write notifications",
        streamId = lsquic_stream_id(stream.quicStream), error = osErrorLabel(writeErrno)

template raiseIfReadReset(stream: Stream) =
  if stream.readResetByPeer():
    raise stream.newStreamResetError("stream read")

template raiseIfReadFailed(stream: Stream) =
  if stream.readFailure.len > 0:
    raise newException(StreamError, stream.readFailure)

template raiseIfWriteReset(stream: Stream) =
  if stream.writeResetByPeer():
    raise stream.newStreamResetError("stream write")

template processWhenAvailable(stream: Stream) =
  if not isNil(stream.doProcess):
    stream.doProcess(true)

proc requestClose(stream: Stream): bool {.raises: [].} =
  if stream.closedByEngine or stream.quicStream.isNil or stream.closeRequested:
    return true

  stream.closeRequested = true
  let ret = lsquic_stream_close(stream.quicStream)
  if ret != 0:
    let closeErrno = errno
    if closeErrno == EBADF:
      stream.processWhenAvailable()
      return true

    stream.closeRequested = false
    trace "Failed to close stream",
      streamId = lsquic_stream_id(stream.quicStream), error = osErrorLabel(closeErrno)
    return false

  stream.processWhenAvailable()
  true

proc closeIfDone*(stream: Stream): bool {.raises: [].} =
  if stream.closeWrite and (stream.isEof or stream.readResetByPeer()):
    return stream.requestClose()

  true

proc abort*(stream: Stream) =
  ## Fails local operations and closes the native stream. The peer may receive
  ## FIN; use `reset` to abort the sending direction instead.
  stream.closeWrite = true
  stream.markReadFailed("stream aborted")
  stream.abortPendingWrites("stream aborted")
  stream.failPendingRead(newException(StreamError, stream.readFailure))
  discard stream.requestClose()
  if not stream.closed.isSet():
    stream.closed.fire()

proc reset*(stream: Stream) {.raises: [].} =
  ## Aborts both directions, sending RESET_STREAM and STOP_SENDING where the
  ## stream state permits. A sending side already closed with FIN stays closed.
  if stream.canWrite and not stream.closedByEngine and not stream.quicStream.isNil and
      not stream.closeRequested:
    lsquic_stream_maybe_reset(stream.quicStream, 0, 1)
  stream.abort()

proc close*(stream: Stream) {.async: (raises: [StreamError, CancelledError]).} =
  if stream.closeWrite or stream.closedByEngine:
    return

  # Closing only the write side
  let ret = lsquic_stream_shutdown(stream.quicStream, 1)
  if ret == 0:
    stream.abortPendingWrites("stream closed")
    stream.closeWrite = true
    if not stream.closeIfDone():
      stream.abort()
      raise newException(StreamError, "could not close the stream")
    if not stream.isEof:
      stream.doProcess(true)
  else:
    raise newException(StreamError, "could not close the stream")

proc readOnce*(
    stream: Stream, dst: ptr byte, dstLen: int
): Future[int] {.async: (raises: [CancelledError, StreamError]).} =
  if not stream.canRead:
    raise newException(StreamError, "stream is write-only")

  if dstLen < 0:
    raiseAssert "dstLen cannot be negative"

  if dstLen == 0:
    return 0

  if dst.isNil:
    raiseAssert "dst cannot be nil"

  raiseIfReadReset(stream)
  raiseIfReadFailed(stream)

  if stream.isEof:
    if not stream.closeIfDone():
      stream.abort()
      raise newException(StreamError, "could not close the stream")
    return 0
  if stream.closedByEngine:
    raise newException(StreamError, "stream closed before end of stream")

  await stream.readLock.acquire()

  defer:
    try:
      stream.readLock.release()
    except AsyncLockError:
      discard # should not happen - lock acquired directly above

  raiseIfReadReset(stream)
  raiseIfReadFailed(stream)

  # In case stream was closed while waiting for lock being acquired
  if stream.closedByEngine:
    raise newException(StreamError, "stream closed before end of stream")

  var receivedFin = false
  let n = readFromStream(stream.quicStream, dst, dstLen, receivedFin)
  if receivedFin:
    stream.isEof = true

  if n == 0:
    if stream.isEof:
      if not stream.closeIfDone():
        stream.abort()
        raise newException(StreamError, "could not close the stream")
      return 0
  elif n > 0:
    return n

  if n < 0 and errno == ECONNRESET:
    if not stream.readResetByPeer():
      stream.markResetByPeer(ResetRead)
    raise stream.newStreamResetError("stream read")

  if n < 0 and errno != EWOULDBLOCK:
    stream.abort()
    raise newException(StreamError, "could not read: " & $errno)

  if lsquic_stream_wantread(stream.quicStream, 1) == -1:
    stream.abort()
    raise newException(StreamError, "could not set wantread")

  let doneFut =
    Future[int].Raising([CancelledError, StreamError]).init("Stream.readOnce")
  stream.toRead = Opt.some(ReadTask(data: dst, dataLen: dstLen, doneFut: doneFut))

  try:
    stream.doProcess(false)
    return await doneFut
  finally:
    stream.clearPendingRead(doneFut)

template readOnce*(stream: Stream, dst: var openArray[byte]): untyped =
  ## Convenience helper that forwards an openArray/seq to the pointer-based API.
  (if dst.len == 0: stream.readOnce(nil, 0)
  else: stream.readOnce(dst[0].addr, dst.len))

proc write*(
    stream: Stream, src: ptr byte, srcLen: int
) {.async: (raises: [CancelledError, StreamError]).} =
  ## Writes from a caller-owned buffer. Counterpart of `readOnce`, and the only
  ## overload that never copies - `WriteTask` holds a pointer to the buffer, not
  ## a copy of it.
  ##
  ## The buffer must stay alive and unmodified until the returned future is
  ## *finished*. Cancelling is not enough on its own: `on_write` reads the
  ## buffer from the engine callback, while the pending write is only cleared
  ## when this proc resumes on a later poll tick. Freeing the buffer between
  ## `cancel()` and that tick is a use-after-free - use `await fut.cancelAndWait()`
  ## or otherwise wait for the future to finish before releasing it.
  if not stream.canWrite:
    raise newException(StreamError, "stream is read-only")

  if srcLen == 0:
    return

  if src.isNil:
    raiseAssert "src cannot be nil"

  raiseIfWriteReset(stream)

  if stream.closeWrite or stream.closedByEngine:
    raise newException(StreamError, "stream closed")

  await stream.writeLock.acquire()

  defer:
    try:
      stream.writeLock.release()
    except AsyncLockError:
      discard # should not happen - lock acquired directly above

  raiseIfWriteReset(stream)

  if stream.closeWrite or stream.closedByEngine:
    raise newException(StreamError, "stream closed")

  # Try to write immediately
  let n = lsquic_stream_write(stream.quicStream, src, srcLen.csize_t)
  if n >= srcLen:
    if lsquic_stream_flush(stream.quicStream) != 0:
      stream.abort()
      raise newException(StreamError, "could not flush stream")
    stream.doProcess(srcLen >= WriteFlushBytes)
    return
  elif n < 0:
    if errno == ECONNRESET:
      if not stream.writeResetByPeer():
        stream.markResetByPeer(ResetWrite)
      raise stream.newStreamResetError("stream write")
    trace "Failed to write to stream",
      streamId = lsquic_stream_id(stream.quicStream), error = osErrorLabel(errno)
    raise newException(StreamError, "could not write")

  # Enqueue otherwise
  if lsquic_stream_wantwrite(stream.quicStream, 1) == -1:
    stream.abort()
    raise newException(StreamError, "could not set wantwrite")

  let doneFut = Future[void].Raising([CancelledError, StreamError]).init("Stream.write")
  stream.toWrite =
    Opt.some(WriteTask(data: src, dataLen: srcLen, doneFut: doneFut, offset: n))

  try:
    stream.doProcess(srcLen >= WriteFlushBytes)
    await doneFut
  finally:
    stream.clearPendingWrite(doneFut)

proc write*(
    stream: Stream, data: sink seq[byte]
) {.async: (raises: [CancelledError, StreamError]).} =
  ## `sink` so that handing over a temporary - `write(@[header])`, or a freshly
  ## built buffer - moves into the async environment instead of being copied
  ## into it. `data` then lives in that environment for the whole call, which is
  ## what keeps the buffer alive for the pointer overload above.
  ##
  ## A caller that keeps its own buffer still pays one copy here, and should use
  ## the pointer overload instead if it can honour that overload's contract.
  if not stream.canWrite:
    raise newException(StreamError, "stream is read-only")

  if data.len == 0:
    return
  await stream.write(data[0].addr, data.len)
