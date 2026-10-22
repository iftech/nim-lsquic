# Complete-stack comparison — 2026-10-22

Comparing the pre-migration nim-lsquic and its original resolved Chronos version
with both proposed libraries shows a small, consistent bulk regression in this
Linux loopback workload: median throughput falls 1.5%, and CPU time per GB rises
1.4%. All twelve paired comparisons have lower proposal throughput. RTT medians
and tails improve in this run. This is a measured tradeoff, not performance parity.

Earlier experiments held the Chronos dependency constant to isolate the
nim-lsquic migration. They did not answer whether the complete proposed stack
regresses against the original stack. This comparison addresses that limitation.

The [three-way attribution follow-up](udp-migration-threeway-2026-10-22.md) adds
old nim-lsquic on the unmodified Chronos PR base to separate the preceding
dependency update from our combined PR changes.

## Compared stacks

| Component | Before migration | Latest proposal |
|---|---|---|
| nim-lsquic | `6622ec2fe12b5c5ac6dc6c1589be8a3a74e3742b` | `869e1db9c7a105d64afc763609d14ee9bb026474` |
| Chronos | 4.4.0, `55adad164db35f7f6973177c5b5ff48fcd6b6450` | `021d28eadf7adeaa9af0a567dd89ed7301cf64f1` |
| Native lsquic | `fd0d75c6584eb4c20dfa8b4b865bfe3daf5a2e52` | Same |
| Nim compiler | 2.2.6, `ab00c56904e3126ad826bb520d243513a139436a` | Same |
| Other dependencies | Original workspace's resolved paths | Identical |

The pre-migration manifest declares `chronos >= 4.0.4`, not an exact revision.
The original workspace's `nimble.paths` resolves Chronos 4.4.0; that is the
concrete baseline used here. Its package metadata records the release revision
above, and all 49 installed package files were verified byte-for-byte against
that Git revision. No proposed Chronos code is present in the baseline.

After substituting only the nim-lsquic and Chronos roots, the two dependency-path
manifests are identical. Both builds use `--noNimblePath` and explicit paths to
prevent the resolver from silently selecting a different dependency. The
nim-lsquic build configuration is unchanged between the two revisions.

The proposal contains the retained Linux `recvfrom(MSG_TRUNC)` optimization and
one-time capture of the bound local address. Rejected send-initialization and
address-conversion experiments are absent. The comparison includes other Chronos
changes since 4.4.0; it measures the combined upgrade rather than attributing the
result solely to the UDP API change.

## Method

- Fresh, separate builds of the identical
  [benchmark source](bench_udp_migration.nim), with source SHA-256
  `af146caa32c7f3dabd28adb85236553393c7cde9b16669ed51d0794f6188ad4d`.
- Release flags: `-d:release --mm:orc --threads:on
  -d:chronicles_log_level=ERROR`. Compiler and all non-Chronos dependencies match.
- Linux 7.0.0-38-generic, Intel Core Ultra 7 155H; both QUIC endpoints run in one
  process on loopback, pinned to CPU 0. CPU frequency is not locked and CPU 0 is
  not reserved. No compilation or test suite ran concurrently with measurements.
- One discarded warmup pair, then **twelve** measured pairs, alternating which
  stack runs first. The count and order were chosen before the timed runs.
- Each execution transfers 1,000,000,000 bytes in 65,536-byte stream chunks, then
  measures 20,000 sequential round trips each at 64 and 1,200 application bytes.
  Each latency workload has 100 additional unmeasured warmup round trips.
- Connection setup and cleanup are excluded from measured intervals. CPU time
  covers both endpoints. Bulk timing includes initial stream activation.
- Values below are medians of twelve runs; RTT columns are medians of per-run
  percentiles, not pooled percentiles. Changes are ratios of the reported medians.

## Results

| Metric | Before migration | Latest proposal | Change |
|---|---:|---:|---:|
| 1 GB throughput (Mbit/s) | 3824.804 | 3768.756 | -1.5% |
| 1 GB CPU time (s) | 2.091 | 2.119 | +1.4% |
| 64-byte RTT p50 (µs) | 13.598 | 13.215 | -2.8% |
| 64-byte RTT p95 (µs) | 14.809 | 14.503 | -2.1% |
| 64-byte RTT p99 (µs) | 19.464 | 17.438 | -10.4% |
| 64-byte CPU time / 20,000 RTTs (ms) | 276.964 | 268.684 | -3.0% |
| 1,200-byte RTT p50 (µs) | 14.380 | 14.060 | -2.2% |
| 1,200-byte RTT p95 (µs) | 16.192 | 15.847 | -2.1% |
| 1,200-byte RTT p99 (µs) | 22.105 | 21.783 | -1.5% |
| 1,200-byte CPU time / 20,000 RTTs (ms) | 294.856 | 288.700 | -2.1% |

The median paired throughput change is **-1.45%**, close to the -1.47% ratio
of medians. Individual pair changes in trial order were -1.73%, -2.73%, -1.40%,
-1.50%, -3.69%, -1.58%, -0.90%, -0.86%, -1.30%, -0.55%, -1.59%, -0.50%.
The proposal is slower in all twelve pairs. Baseline throughput ranges from
3,795 to 3,858 Mbit/s; proposal throughput ranges from 3,712 to 3,809 Mbit/s.

The result supports a small bulk-throughput/CPU regression for this complete-stack
upgrade in the measured workload. The improved latency does not cancel that
cost; whether the tradeoff is acceptable requires a representative workload and
maintainer agreement. Keep both PRs in draft rather than claiming no regression.

This does not establish an exact regression size outside this environment.
Physical-network throughput, concurrent connections, latency under bulk load,
packet loss and Windows/macOS performance remain unmeasured here. The earlier
same-Chronos experiments remain useful for diagnosis, but this is the relevant
comparison for the combined upgrade against the original resolved stack.

## Raw data and reproduction

[Raw CSV](udp-migration-2026-10-22-fullstack.csv) contains all 78 workload records,
including the six records from the discarded warmup pair. `trial=0` is excluded
from summaries; `position=0` means first in a pair. Each execution has a UTC start
timestamp. All 26 executions completed the benchmark's exact bulk-byte-count
and round-trip-count checks successfully. CSV records were checked against the
raw JSON output.

Build the same source at the two nim-lsquic revisions above, selecting each
stack's Chronos version with an explicit `--path` and keeping all other paths
identical. Pin each binary with `taskset -c 0` and run sequentially:

```text
warmup: before, proposal
odd trials 1, 3, 5, 7, 9, 11: proposal, before
even trials 2, 4, 6, 8, 10, 12: before, proposal
```

Other dependencies: results 0.5.1, serialization 0.5.4, unittest2 0.2.5,
boringssl 0.0.11 (`dee1decd`), stew 0.5.2, bearssl 0.2.13,
json_serialization 0.4.5, faststreams 0.5.2, httputils 0.5.1,
chronicles 0.12.4, testutils 0.8.3, zlib 0.2.0.

Built executable SHA-256 hashes:

- Before: `3b04a1e8335f508bc5f01147432b105fbc02b4217d8cd5e150f032ec833c1428`
- Proposal: `6e68ffbf8f005d43ec922ee9739dc83ce7e3bf66d9ab1cd3559928d8a4361321`
