# Legacy API control and bulk profile — 2026-10-22

Keeping old nim-lsquic on the proposed Chronos implementation produces essentially
unchanged bulk performance. Switching that same Chronos build to the migrated
nim-lsquic path lowers median throughput by 1.97% and raises CPU time per GB by
1.91%. The proposal is slower in eleven of twelve matched rounds.

This isolates the cost to adopting the new UDP path, which includes both the
nim-lsquic adapter and the newly exercised Chronos implementation. It does not
assign the whole cost to either repository or to a particular function.

## Controls and measurements

| Label | nim-lsquic | Chronos | UDP path |
|---|---|---|---|
| A — PR base | `6622ec2` | `2684ae4` | Original manual drain and raw sends |
| B — Legacy control | `6622ec2` | `021d28e` | Original manual drain and raw sends |
| C — Proposal | `869e1db` | `021d28e` | Synchronous receive and direct batch API |

The [previous three-way experiment](udp-migration-threeway-2026-10-22.md)
separated the preceding Chronos upgrade from our combined PR changes. This
experiment adds the missing control: B changes only Chronos relative to A,
and C changes nim-lsquic relative to B. Later proposal commits contain reports
only. All non-Chronos dependencies, native lsquic, compiler and flags match
[the full-stack experiment](udp-migration-fullstack-2026-10-22.md).

The unchanged [benchmark](bench_udp_migration.nim) transfers 1 GB and measures
20,000 sequential RTTs each at 64 and 1,200 bytes, following 100 warmup RTTs.
Both endpoints run in one process on Linux loopback pinned to CPU 0. One warmup
triple is discarded; twelve measured triples use all six permutations twice.
Binaries execute sequentially without concurrent compilation or tests. CPU 0
is not reserved and frequency is not locked. The run count was fixed beforehand.

Values are medians of twelve executions; latency figures are medians of each
run's percentiles, not pooled quantiles. CPU time covers both endpoints, excludes
connection setup/cleanup and includes initial stream activation for bulk.

| Metric | A — PR base | B — Legacy control | C — Proposal |
|---|---:|---:|---:|
| Bulk throughput (Mbit/s) | 3840.220 | 3845.517 | 3769.626 |
| CPU seconds / GB | 2.082 | 2.080 | 2.120 |
| 64-byte RTT p50 (µs) | 13.472 | 13.422 | 13.225 |
| 64-byte RTT p95 (µs) | 14.534 | 14.465 | 14.258 |
| 64-byte RTT p99 (µs) | 17.953 | 17.700 | 16.971 |
| 1200-byte RTT p50 (µs) | 14.157 | 14.188 | 14.015 |
| 1200-byte RTT p95 (µs) | 15.414 | 15.834 | 15.471 |
| 1200-byte RTT p99 (µs) | 19.292 | 20.003 | 19.980 |

| Transition | Throughput change, ratio of medians | Median matched change | Slower rounds |
|---|---:|---:|---:|
| B vs A: Chronos PR with old consumer | +0.14% | +0.03% | 6 / 12 |
| C vs B: adopt the new UDP API | -1.97% | -1.87% | 11 / 12 |

Matched C-vs-B changes range from -2.91% to +0.67%. Bulk performance parity is
not established. RTT p50 improves in this run, while previous experiments have
shown varying tail results; this is not a general latency improvement claim.

## Separate bulk-only profile

After timing finished, two separate builds used `--passC:-pg --passL:-pg`,
with the same release/ORC/compiler/dependency configuration. The benchmark
source was changed only to transfer 3 GB and omit both ping invocations.
Three alternating pairs (BC, CB, BC), pinned to CPU 0, transferred 9 GB per
variant. All transfers completed with exact byte-count assertions. The
instrumented binaries were never used for the table above.

The aggregate gprof call graph identifies a concrete source of extra work:
C's `sendPacketsOut` calls `toTransportAddress` 6,424,966 times, whereas B's
send callback forwards the socket address directly. Chronos then converts
that transport address back through `setRemoteAddress`/`toSAddr` for sending.
Receive-side address decoding exists in both variants.

| Function / operation | B calls across 9 GB | C calls across 9 GB |
|---|---:|---:|
| `fromSAddr` — all socket-address decodes | 6,423,262 | 12,849,944 |
| `toSAddr` — all socket-address encodes | 12,846,464 | 19,274,862 |
| `setRemoteAddress` | 0 | 6,424,966 |
| `sendPacketsOut` | 243,407 | 245,116 |
| `trySendBatch` | 0 | 245,116 |
| Receive drain callback | 146,040 | 148,323 |
| Chronos `localAddress2` | 146,046 | 12 |

The cached bound address removes repeated local-address lookups as intended.
Packet counts are close (about 6.42 million per variant); the doubled decode
count is not explained by twice as many packets. Drain callbacks increase
about 1.6%; the old first-packet-plus-drain path and new total-budget path have
different grouping, which remains another possible contributor.

The send callback's sampled self time is 0.03 s in B versus 0.04 s in C, with
another 0.07 s in `trySendBatch` and 0.08 s in `setRemoteAddress`. C's gprof
call graph assigns approximately 0.34 s including descendants to the send
callback, versus 0.03 s for B. These coarse figures identify work to investigate,
not a measurement of how much of the uninstrumented regression it causes.
The address helper also runs on B's receive path, so its whole-program self
time must not be mistaken for new send cost.

`perf` is unavailable under the machine's current restrictions; no system
settings were changed. gprof samples user-space time at 10 ms resolution,
omits kernel costs, and instrumentation alters execution and scheduling.
Total sampled time is 4.22 s for B and 4.64 s for C across all three runs;
these totals are not an end-to-end performance comparison. The counts and
source establish extra conversions, but do not establish that removing them
would recover the entire 1.97% throughput loss. The earlier small helper
optimization did not produce a repeatable QUIC gain and remains reverted.

The next useful optimization experiment is to eliminate the send-side address
round trip and descriptor rebuilding together, then rerun an uninstrumented
B/current/candidate comparison. Any raw-address entry point would need to retain
Chronos queue ordering, dual-stack normalization and partial-send behavior;
it should not be added to the public API solely on this profile evidence.
No runtime changes were made in this experiment. Both PRs remain drafts.

## Artifacts and reproduction

[Timing CSV](udp-migration-2026-10-22-legacy-control.csv) contains all 117
records, including nine warmups. Exclude `trial=0`; compare matching trial
numbers. All 39 executions completed the bulk byte count and RTT counts.
[Profile CSV](udp-migration-2026-10-22-legacy-profile.csv) contains gprof flat
entries with call counts; uncounted assembly symbols are omitted. Self times
are samples, and a zero does not mean a function is free.

Build A and C as described in the earlier reports. Build B from the original
nim-lsquic source with the proposed Chronos path, changing only output/cache
paths from A's arguments. All three share the exact benchmark source.
B binary SHA-256: `c141ce9987972d660446ac215e49c17df736e4d71a5bf493d06c6db666a5fad2`.

Run with `taskset -c 0`: warmup ABC, then ABC/ACB/BAC/BCA/CAB/CBA twice.
For profiles, generate the bulk-only source changes described above, add the
`-pg` compiler/linker flags with separate cache/output paths, and run BC/CB/BC.
Set a distinct `GMON_OUT_PREFIX` for every execution; aggregate the three
profile files per binary with `gprof -b -p` (flat) and `gprof -b -q` (call graph).

These results cover one Linux loopback workload, not physical-network,
multi-connection, packet-loss, Windows or macOS performance.
