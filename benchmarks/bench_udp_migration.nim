# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

# Run identical copies against the old and migrated UDP implementations.
import std/[algorithm, json, times]
import chronos
import ../lsquic
import ../tests/helpers/clientserver

const
  BulkBytes = 1_000_000_000
  ChunkBytes = 65536
  PingCount = 20000
  WarmupCount = 100

proc readFull(stream: Stream, data: pointer, size: int) {.async.} =
  let buffer = cast[ptr UncheckedArray[byte]](data)
  var offset = 0
  while offset < size:
    let count = await stream.readOnce(addr buffer[offset], size - offset)
    doAssert count > 0
    offset += count

proc bulk() {.async.} =
  let peers = await connectPeers()
  let outgoing = await peers.outgoing.openStream()
  proc serve() {.async.} =
    let incoming = await peers.incoming.incomingStream()
    var request = newSeq[byte](1)
    await incoming.readFull(addr request[0], request.len)
    var remaining = BulkBytes
    while remaining > 0:
      let count = min(remaining, ChunkBytes)
      await incoming.write(newSeq[byte](count))
      remaining -= count
    await incoming.close()

  let serving = serve()
  var buffer = newSeq[byte](ChunkBytes)
  let
    cpuStart = cpuTime()
    start = Moment.now()
  await outgoing.write(@[1'u8])
  var received = 0
  while received < BulkBytes:
    let count = await outgoing.readOnce(addr buffer[0], buffer.len)
    doAssert count > 0
    received += count
  doAssert received == BulkBytes
  let
    elapsed = (Moment.now() - start).nanoseconds.float / 1e9
    cpu = cpuTime() - cpuStart
  await serving
  echo $(
    %*{
      "workload": "bulk",
      "bytes": BulkBytes,
      "seconds": elapsed,
      "cpu_seconds": cpu,
      "mbps": BulkBytes.float * 8 / elapsed / 1e6,
    }
  )
  await peers.stop()

proc ping(size: int) {.async.} =
  let peers = await connectPeers()
  let outgoing = await peers.outgoing.openStream()
  proc serve() {.async.} =
    let incoming = await peers.incoming.incomingStream()
    var data = newSeq[byte](size)
    for i in 0 ..< WarmupCount + PingCount:
      await incoming.readFull(addr data[0], data.len)
      await incoming.write(data)

  let serving = serve()
  var
    payload = newSeq[byte](size)
    reply = newSeq[byte](size)
    samples = newSeq[int64](PingCount)
  for i in 0 ..< WarmupCount:
    await outgoing.write(payload)
    await outgoing.readFull(addr reply[0], reply.len)
  let cpuStart = cpuTime()
  for i in 0 ..< PingCount:
    let start = Moment.now()
    await outgoing.write(payload)
    await outgoing.readFull(addr reply[0], reply.len)
    samples[i] = (Moment.now() - start).nanoseconds
  let cpu = cpuTime() - cpuStart
  await serving
  samples.sort()
  echo $(
    %*{
      "workload": "ping",
      "message_bytes": size,
      "samples": PingCount,
      "cpu_seconds": cpu,
      "p50_us": samples[PingCount div 2].float / 1e3,
      "p95_us": samples[PingCount * 95 div 100].float / 1e3,
      "p99_us": samples[PingCount * 99 div 100].float / 1e3,
    }
  )
  await peers.stop()

initializeLsquic(true, true)
waitFor bulk()
waitFor ping(64)
waitFor ping(1200)
cleanupLsquic()
