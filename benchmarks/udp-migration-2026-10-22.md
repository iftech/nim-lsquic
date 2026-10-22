# UDP migration comparison — 2026-10-22

The truncation address fix is independent of this performance experiment. This
comparison measures the original nim-lsquic manual UDP drain implementation
against the Chronos migration, not against ordinary per-packet Chronos delivery.

The [profiling follow-up](udp-migration-profile-2026-10-22.md) records subsequent
experiments and the remaining gap after two targeted receive-path changes.

## Method

- Baseline: nim-lsquic `6622ec2fe12b5c5ac6dc6c1589be8a3a74e3742b`.
- Migrated: nim-lsquic `ec999b2352c58aff78e9dde56578ce52bd3f9b8f`.
- Both use Chronos `2f8dd968f167e96a481cf4dc739c3f92df5cb20e` and the
  same native lsquic sources and dependencies. The baseline retains its manual
  receive drain and raw send callbacks; using the same Chronos eliminates
  dependency-version differences from the comparison.
- Nim 2.2.6, `-d:release --mm:orc --threads:on
  -d:chronicles_log_level=ERROR`. Identical copies of
  [bench_udp_migration.nim](bench_udp_migration.nim) were compiled in each checkout.
- Linux 7.0.0-38-generic, Intel Core Ultra 7 155H. Both endpoints run in one
  process on loopback, pinned to CPU 0. CPU frequency was not locked, and the
  machine was not otherwise isolated.
- One discarded warmup pair, then six measured pairs, alternating old/new and
  new/old execution order. Binaries run sequentially, never concurrently.
- Each execution transfers 1,000,000,000 bytes over one QUIC stream in 65,536-byte
  chunks, then measures 20,000 sequential round trips each at 64 and 1,200
  application bytes. Each latency workload has 100 unmeasured warmup round trips.
- Connection setup and cleanup are excluded from the measured intervals.
  CPU time includes both client and server, including encryption and stream work.
  Bulk timing includes initial stream activation; latency is measured after warmup.
- A preliminary 100 MB / 2,000-RTT run showed substantial variation; the longer
  workload above was selected before collecting these final results.

## Initial results

Values below are medians of the six runs. RTT columns are medians of per-run
percentiles, not percentiles pooled across all runs. Change is the ratio of the
reported medians; higher throughput is better, lower CPU time and RTT are better.

| Metric | Original | Migrated | Change |
|---|---:|---:|---:|
| 1 GB throughput (Mbit/s) | 3595.501 | 3250.207 | -9.6% |
| 1 GB CPU time (s) | 2.224 | 2.462 | +10.7% |
| 64-byte RTT p50 (µs) | 13.845 | 14.621 | +5.6% |
| 64-byte RTT p95 (µs) | 17.456 | 16.556 | -5.2% |
| 64-byte RTT p99 (µs) | 21.286 | 20.654 | -3.0% |
| 64-byte CPU time / 20,000 RTTs (ms) | 287.669 | 297.496 | +3.4% |
| 1,200-byte RTT p50 (µs) | 14.884 | 14.998 | +0.8% |
| 1,200-byte RTT p95 (µs) | 18.179 | 17.568 | -3.4% |
| 1,200-byte RTT p99 (µs) | 23.617 | 22.913 | -3.0% |
| 1,200-byte CPU time / 20,000 RTTs (ms) | 302.134 | 305.734 | +1.2% |

The median paired throughput change is -4.1%.
Individual pair changes were -6.2%, -2.0%, -6.9%, -16.2%, +0.9%, +1.9%.
Original bulk throughput ranged from 2,643 to 3,780 Mbit/s; migrated throughput
ranged from 2,666 to 3,536 Mbit/s. The difference between the paired statistic and
the ratio of medians is another reason not to treat this as a precise effect size.

The results flag a possible bulk-throughput/CPU regression. They do not establish
performance parity or a statistically reliable regression magnitude. Latency
results are mixed and variable. Keep the migration in draft until the bulk result
is understood with profiling and a more controlled repeat. The new send path
adds descriptor/address conversion and initializes scratch arrays that the old
path left uninitialized; these are inspection-based profiling candidates, not
measured causes.

This is a single-process Linux loopback experiment. It does not measure physical
network behavior, concurrent connections, latency under bulk load, packet loss,
or Windows/macOS performance.

## Idle-machine repeat

The same binaries and runner were repeated after the user stopped using the
machine. Workload, CPU 0 affinity, warmup and six alternating measured pairs were
unchanged. CPU frequency remained unlocked and the CPU was not reserved; this
reduces foreground interference without establishing a fully isolated environment.
The original results above are preserved.

| Metric | Original | Migrated | Change |
|---|---:|---:|---:|
| 1 GB throughput (Mbit/s) | 3783.901 | 3593.138 | -5.0% |
| 1 GB CPU time (s) | 2.114 | 2.226 | +5.3% |
| 64-byte RTT p50 (µs) | 13.547 | 13.739 | +1.4% |
| 64-byte RTT p95 (µs) | 14.784 | 15.166 | +2.6% |
| 64-byte RTT p99 (µs) | 18.341 | 18.871 | +2.9% |
| 64-byte CPU time / 20,000 RTTs (ms) | 276.714 | 279.066 | +0.8% |
| 1,200-byte RTT p50 (µs) | 14.226 | 14.771 | +3.8% |
| 1,200-byte RTT p95 (µs) | 15.682 | 16.900 | +7.8% |
| 1,200-byte RTT p99 (µs) | 20.048 | 22.500 | +12.2% |
| 1,200-byte CPU time / 20,000 RTTs (ms) | 291.938 | 301.704 | +3.3% |

All six pairs showed lower migrated bulk throughput: -6.3%, -4.5%, -4.3%,
-4.7%, -3.9%, -6.8%, with a median paired change of -4.6%. Original throughput
ranged from 3,733 to 3,848 Mbit/s; migrated throughput ranged from 3,584 to
3,614 Mbit/s. These ranges are substantially narrower than in the initial run.

The repeat supports a reproducible bulk regression in this loopback workload:
median throughput falls 5.0% and CPU time rises 5.3%. Foreground activity may
have contributed to the earlier variability, but does not explain the remaining
gap. RTT medians and tails also increase in this repeat. This does not identify
the cause or establish the effect on other workloads; profiling is the next step.
Keep the migration in draft pending investigation.

[Idle-repeat raw CSV](udp-migration-2026-10-22-idle.csv) includes all 42 workload
records, including the discarded warmup pair. Summary calculations use only the
six measured pairs and the same median definitions as the initial run.

## Reproduction and raw data

[Raw CSV](udp-migration-2026-10-22.csv) includes all measured runs and the discarded
warmup pair. Trial 0 is the discarded pair. Each binary emits its workload records
as JSON; the runner adds variant, trial, warmup and CPU-affinity fields.

Copy the benchmark source into the baseline checkout without modifying its
implementation. Resolve identical dependencies in both checkouts, select the same
Chronos source with `--path`, and build each with the flags above. Pin both binaries
to the same CPU (for example `taskset -c 0`) and run sequentially in this order:

```text
warmup: old, new
trial 1: new, old
trial 2: old, new
trial 3: new, old
trial 4: old, new
trial 5: new, old
trial 6: old, new
```

Dependencies used: results 0.5.1, serialization 0.5.4, unittest2 0.2.5,
boringssl 0.0.11 (`dee1decd`), stew 0.5.2, bearssl 0.2.13,
json_serialization 0.4.5, faststreams 0.5.2, httputils 0.5.1,
chronicles 0.12.4, testutils 0.8.3, zlib 0.2.0. Native lsquic was
`fd0d75c6584eb4c20dfa8b4b865bfe3daf5a2e52` in both builds.
