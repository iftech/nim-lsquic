# Three-way attribution comparison — 2026-10-22

The added control places the measured bulk cost in the combined UDP extraction
and migration, rather than in the preceding Chronos update. Old nim-lsquic on
the unmodified Chronos PR base has 0.35% higher median throughput than on Chronos
4.4.0. The proposal is 1.77% slower than that control, with 1.79% more CPU time
per GB. It is slower in eleven of twelve matched rounds.

This localizes the cost to our combined PR changes. It does not yet identify a
particular function or separate the Chronos PR implementation from the
nim-lsquic adapter. Latency remains workload-dependent: median RTT improves,
but the 1,200-byte RTT tail is worse in this run.

## Stacks

| Label | nim-lsquic | Chronos | Purpose |
|---|---|---|---|
| A — Original | `6622ec2` | 4.4.0, `55adad1` | Original resolved stack |
| B — PR-base control | `6622ec2` | Unmodified `2684ae4` | Isolate Chronos changes preceding our PR |
| C — Proposal | `869e1db` | `021d28e` | Combined extraction and migration |

Chronos `2684ae46417f2daca430e0fad776d20f6b2acda1` is the parent of the first
UDP extraction commit, `c55c28c`, and the branch's merge base. It was checked out
in a separate, clean repository. The control uses the original manual receive
drain and raw send implementation; none of the proposed Chronos UDP changes are
present in B.

The original and proposal binaries are the exact binaries from the
[complete-stack comparison](udp-migration-fullstack-2026-10-22.md), verified by
SHA-256 before the run. Subsequent proposal commits contain benchmark reports
only. Full source revisions, original dependency provenance and common native
lsquic/dependency versions are recorded in that report.

B was built with the same source, compiler and flags as A; the only build
argument differences are its Chronos path, output path and compiler-cache path.
All three use identical benchmark source and non-Chronos dependencies.

## Method

The unchanged [QUIC benchmark](bench_udp_migration.nim) transfers 1 GB, then
measures 20,000 sequential round trips each at 64 and 1,200 application bytes.
There are 100 unmeasured warmup RTTs per latency workload. Both QUIC endpoints
run in one process on Linux loopback, pinned to CPU 0. The compiler is Nim 2.2.6,
with `-d:release --mm:orc --threads:on -d:chronicles_log_level=ERROR`.

One discarded warmup triple is followed by twelve measured triples. All six
execution-order permutations are used twice, so each variant occupies each
position four times. The run count and schedule were fixed before collection.
Binaries run sequentially; no compilation or test suite ran concurrently with
measurements. CPU frequency is not locked and CPU 0 is not reserved.

CPU time covers both endpoints. Connection setup and cleanup are excluded;
bulk timing includes initial stream activation. Values below are medians of
twelve executions. RTT percentiles are medians of per-run percentiles, not
percentiles pooled across runs.

## Results

| Metric | A — Original | B — PR-base control | C — Proposal |
|---|---:|---:|---:|
| 1 GB throughput (Mbit/s) | 3826.045 | 3839.625 | 3771.536 |
| 1 GB CPU time (s) | 2.090 | 2.083 | 2.120 |
| 64-byte RTT p50 (µs) | 13.559 | 13.436 | 13.242 |
| 64-byte RTT p95 (µs) | 14.593 | 14.541 | 14.243 |
| 64-byte RTT p99 (µs) | 17.652 | 17.077 | 16.895 |
| 64-byte CPU time / 20,000 RTTs (ms) | 276.104 | 273.083 | 268.499 |
| 1,200-byte RTT p50 (µs) | 14.355 | 14.201 | 14.070 |
| 1,200-byte RTT p95 (µs) | 15.901 | 15.722 | 15.953 |
| 1,200-byte RTT p99 (µs) | 19.758 | 19.944 | 21.609 |
| 1,200-byte CPU time / 20,000 RTTs (ms) | 293.658 | 289.480 | 288.639 |

| Comparison | Throughput change, ratio of medians | Median matched change | Slower matched rounds |
|---|---:|---:|---:|
| B vs A: preceding Chronos update | +0.35% | +0.28% | 2 / 12 |
| C vs B: extraction and migration | -1.77% | -2.14% | 11 / 12 |
| C vs A: complete upgrade | -1.42% | -1.29% | 11 / 12 |

B has 0.36% lower median CPU time per GB than A; C has 1.79% higher CPU time
than B and 1.42% higher CPU time than A. The combined-upgrade result is close
to the previous complete-stack experiment's 1.5% throughput loss.

The C-vs-B matched throughput changes, in trial order, are -0.81%, -0.68%,
-2.47%, -2.02%, -0.97%, -3.92%, -2.54%, -2.26%, -2.46%, -1.64%, +0.78%, -2.59%.
The one positive round also has a low B result, illustrating remaining variation.
Do not subtract the matched medians as if they were additive effects; each
comparison is calculated directly from its matched observations.

The preceding Chronos update shows no systematic bulk penalty in this run.
The evidence instead points to the combined PR changes as the source of the
bulk-throughput cost. This is not evidence against a specific helper, syscall
or scheduling decision. In particular, B-vs-C changes both the Chronos code and
the nim-lsquic adapter. A finer attribution requires a further control or profile.

C improves RTT p50 by 1.44% at 64 bytes and 0.93% at 1,200 bytes relative to B.
However, 1,200-byte RTT p99 increases 8.35% relative to B (9.37% relative to A).
This differs from the preceding run's tail result, so a blanket latency-improvement
claim is not supported across runs. Keep the migration in draft: the bulk cost
is measurable, and performance parity is not established.

## Raw data and reproduction

[Raw CSV](udp-migration-2026-10-22-threeway.csv) contains all 117 workload records,
including nine warmup records. `trial=0` is excluded from summaries. `position`
is the zero-based execution position within a triple, and `started_utc` records
each execution's start time. All 39 executions completed the exact bulk transfer
and expected round-trip counts; CSV records were checked against the raw JSON.

Compile A and C as described in the complete-stack report. For B, use A's
nim-lsquic source and dependency paths, replacing only the Chronos path with a
clean checkout of `2684ae46417f2daca430e0fad776d20f6b2acda1`. Use separate output
and compiler-cache paths. The SHA-256 of the resulting B binary in this run is
`5b82404d427b4470c6e73565598678068dc3488e14fd14c9fd52bf385047af6c`.

Run every binary with `taskset -c 0` in this order:

```text
warmup: ABC
trials 1–6: ABC, ACB, BAC, BCA, CAB, CBA
trials 7–12: ABC, ACB, BAC, BCA, CAB, CBA
```

This experiment measures a single-process Linux loopback workload. It does not
establish effects on physical networks, concurrent connections, latency under
bulk load, packet loss or Windows/macOS performance. CPU affinity and alternating
order reduce interference and order bias but do not create an isolated machine.
