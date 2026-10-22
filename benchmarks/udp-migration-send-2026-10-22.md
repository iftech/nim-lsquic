# Send-address conversion experiment — 2026-10-22

Address conversion has a measurable isolated cost, but a smaller helper did not
produce a repeatable bulk-throughput improvement. The candidate was reverted.
There is no new raw-address API or retained send-path change.

## Focused measurement

[bench_send_address.nim](bench_send_address.nim) measures native IPv4/IPv6 address
copying versus `sockaddr → TransportAddress → sockaddr`. It calls the actual
`toTransportAddress` helper, then Chronos `toSAddr`, from identical benchmark
sources in separate before/after builds. Both use the same compiler, flags and
Chronos checkout. It excludes socket calls, payload work, address normalization
for dual-stack sockets, and batch-message construction; it is not a UDP send
throughput benchmark.

The candidate replaced the temporary address in the helper with its return value:

```nim
proc toTransportAddress*(sock: ptr SockAddr): TransportAddress =
  fromSAddr(cast[ptr Sockaddr_storage](sock), sockAddrLen(sock.sa_family.int), result)
```

Each execution prepares 6,400,000 addresses per case in batches of 64. A GCC
memory barrier after each batch prevents removing output writes or hoisting
input reads. Output addresses are checked after each case. Linux/GCC is required
for this benchmark. Both builds are pinned to CPU 0 and run sequentially, with
one discarded warmup pair and six measured pairs alternating before/after order.
Values below are medians of process CPU nanoseconds per address.

| Address preparation | Before | Candidate |
|---|---:|---:|
| IPv4 native copy | 1.38 ns | 1.37 ns |
| IPv4 conversion round trip | 37.28 ns | 29.15 ns |
| IPv6 native copy | 1.69 ns | 1.71 ns |
| IPv6 conversion round trip | 38.73 ns | 29.46 ns |

The helper saves roughly 8–9 ns per round trip in this focused measurement.
A preliminary comparison of locally defined functions gave different absolute
costs; the final measurement above uses the real imported helper in both builds
to avoid differences caused by compiler scope. Only the final focused results
are in the [raw CSV](udp-migration-2026-10-22-send-address.csv), which contains
56 records, including the discarded warmup pair.

## Full QUIC comparison

The original implementation, current migration with both retained receive
optimizations, and send-helper candidate were compared using the unchanged
[QUIC benchmark](bench_udp_migration.nim). As in the
[previous experiment](udp-migration-profile-2026-10-22.md), one discarded warmup
triple precedes six measured triples in all six execution-order permutations.
Each variant occupies each position twice. All binaries are ordinary release
builds, run sequentially on CPU 0; no compilation or test suite runs concurrently.
CPU frequency is not locked and CPU 0 is not reserved.

| Metric | Original | Current migration | Candidate |
|---|---:|---:|---:|
| 1 GB throughput (Mbit/s) | 3803.24 | 3769.68 | 3753.39 |
| 1 GB CPU time (s) | 2.103 | 2.122 | 2.131 |
| 64-byte RTT p50 (µs) | 13.418 | 13.303 | 13.130 |
| 64-byte RTT p95 (µs) | 15.226 | 14.901 | 14.380 |
| 64-byte RTT p99 (µs) | 20.477 | 19.475 | 18.229 |
| 1,200-byte RTT p50 (µs) | 14.391 | 14.415 | 13.826 |
| 1,200-byte RTT p95 (µs) | 15.703 | 16.259 | 15.651 |
| 1,200-byte RTT p99 (µs) | 19.538 | 22.044 | 20.361 |

Candidate bulk throughput changes versus the current migration were -1.52%,
-0.51%, +1.91%, +0.62%, -1.58%, +2.02%, with a median paired change of +0.05%.
The ratio of median throughputs is -0.43%; CPU time rises 0.44%. Three pairs
improve and three worsen. Latency measurements are better for the candidate in
this run, but the intended bulk-throughput improvement was not demonstrated.
The candidate was reverted rather than treating the isolated conversion saving
as proof of a QUIC throughput gain.

The current migration's throughput is 0.88% below the original in this run;
its median paired change is -1.66%. This differs from the earlier ratio-of-medians
gap of 2.3%, reinforcing that the remaining difference is small and variable.
It does not establish parity or identify conversion as the cause of that gap.
A raw-address API is not justified by this experiment alone.

[Full QUIC raw CSV](udp-migration-2026-10-22-send-quic.csv) contains all 63 records,
including the discarded warmup triple. Summary values are medians of six runs;
RTT columns are medians of per-run percentiles, not pooled percentiles.

## Reproduction

Compiler, native lsquic, dependencies, workload and release flags are listed in
the [original report](udp-migration-2026-10-22.md). The QUIC controls reuse the
existing binaries: `old` is nim-lsquic `6622ec2` with Chronos `2f8dd96`; `cached`
is the code now committed as nim-lsquic `14dc0a8` and Chronos `c9c948b`.
`direct-result` is that current migration with only the helper replacement above.
The intervening Chronos changes outside the retained receive optimization affect
Windows, not these Linux runs.

For the focused benchmark, copy its source into both checkouts and build with
`nim c -d:release --mm:orc --threads:on -d:chronicles_log_level=ERROR`, supplying
the same dependency paths used for the QUIC benchmark. The before build uses the
original helper (verified byte-for-byte identical in `6622ec2` and `14dc0a8`);
the candidate uses the replacement above. Both focused builds use Chronos
`c9c948b`. Run each with `taskset -c 0` in alternating order. Add build, trial,
warmup and CPU fields to the emitted JSON records; discard trial 0 in summaries.

For the full benchmark, the measured orders are ABC, ACB, BAC, BCA, CAB, CBA,
with A=`old`, B=`cached`, C=`direct-result`. The warmup order is ABC.

## Validation and CI follow-up

Both focused builds checked their output addresses successfully; every full QUIC
execution completed the expected transfer and round trips. The send-helper
candidate was fully reverted before committing this report.

CI also exposed a separate Windows compile failure at `endpoint.nim`'s receive
callback: `OSErrorCode` was undeclared. The endpoint now imports the type explicitly
from `std/os`. A Windows-targeted compiler check reproduces the callback failure
without the import and passes with it. After the fix, the full Linux nim-lsquic
suite passes all 146 tests. Native Windows execution remains for CI.
