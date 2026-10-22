# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

# Linux/GCC microbenchmark: address preparation only, without socket syscalls.
import std/[json, times]
import chronos, chronos/osdefs
import ../lsquic/helpers/transportaddr

{.
  emit: """
static void address_bench_barrier(void *p) {
  __asm__ __volatile__("" : : "g"(p) : "memory");
}
"""
.}
proc barrier(p: pointer) {.importc: "address_bench_barrier", nodecl.}

type Variant = enum
  nativeCopy
  conversion

const
  BatchSize = 64
  Batches = 100000

proc measure(variant: static Variant, family: string) =
  var
    source, output: array[BatchSize, Sockaddr_storage]
    lengths: array[BatchSize, SockLen]
  for i in 0 ..< BatchSize:
    let address = initTAddress(family, 10000 + i)
    address.toSAddr(source[i], lengths[i])
  let start = cpuTime()
  for batch in 0 ..< Batches:
    for i in 0 ..< BatchSize:
      let sock = cast[ptr SockAddr](addr source[i])
      when variant == nativeCopy:
        copyMem(addr output[i], sock, sockAddrLen(sock.sa_family.int))
      else:
        sock.toTransportAddress().toSAddr(output[i], lengths[i])
    # Keep all prepared addresses observable and prevent loop hoisting.
    barrier(addr output[0])
    barrier(addr source[0])
  let elapsed = cpuTime() - start
  for i in 0 ..< BatchSize:
    var actual: TransportAddress
    fromSAddr(addr output[i], lengths[i], actual)
    doAssert actual == initTAddress(family, 10000 + i)
  echo $(
    %*{
      "variant": $variant,
      "family": family,
      "packets": BatchSize * Batches,
      "cpu_seconds": elapsed,
      "ns_per_packet": elapsed * 1e9 / (BatchSize * Batches).float,
    }
  )

for family in ["127.0.0.1", "::1"]:
  measure(nativeCopy, family)
  measure(conversion, family)
