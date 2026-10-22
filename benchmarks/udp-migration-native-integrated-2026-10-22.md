# Integrated native-address sends — 2026-10-22

The measured fix is now integrated into both draft PRs. Chronos exposes
`DatagramNativeOut` / `trySendNativeBatch`, sharing the send loop, queue checks,
normalization and prefix/error handling with `trySendBatch`. nim-lsquic passes
borrowed native socket addresses rather than decoding and re-encoding each one.
It pins the exact Chronos revision containing this API and its BSD correction.

Across two twelve-round experiments, the retained implementation and the original
pre-migration stack split their 24 matched bulk comparisons evenly. The combined
median matched throughput change is +0.06%; pooled throughput medians are
3,803.769 Mbit/s originally and 3,811.005 Mbit/s after migration (+0.19%). This
supports recovery of the earlier roughly 2% systematic penalty in this Linux
loopback workload. It does not establish a speedup or formal equivalence.

## Implementation and validation

Native destinations must point to readable IPv4/IPv6 address bytes with the
exact family-specific length. A nil address, unsupported family or incorrect
length reports EINVAL (WSAEINVAL on Windows) after the accepted prefix. Addresses,
fragment descriptors and payloads are borrowed only until the call returns.
Ordinary native sends retain IPv6 scope/flow fields; required dual-stack and
wildcard normalization uses the existing Chronos behavior. Both entry points
share the platform send implementation; the diagnostic duplicate was not kept.

Validation before publication:

- Full Chronos Linux suite: 537 tests, 523 passed, 14 skipped, no failures.
- Full nim-lsquic Linux suite: 146 passed, no failures.
- Direct datagram tests: all 13 pass under ORC and refc/chronosDebug.
- Windows amd64 direct-test cross-compilation passes.
- macOS arm64 semantic/C generation passes; this is not native execution.

New tests cover borrowed buffers/address lifetime, IPv4/IPv6 scatter/gather,
batches beyond 64 packets, empty packets, invalid address lengths/families,
closed transports, successful prefixes before failure, async queue ordering,
dual-stack mapping and wildcard normalization.

Native macOS CI found that sendmsg rejects zero iovecs with EMSGSIZE. The fix
supplies one zero-length iovec on non-Linux POSIX platforms, matching the empty
buffer handling used for Windows. The empty-datagram regression remains enabled.
All 13 direct tests pass locally after the correction. This platform-only change
does not alter the measured Linux path. Native CI for the corrected revision
was still running when this report was written; neither draft is declared ready
to merge on the strength of cross-compilation alone.

## Measurement method

The unchanged [benchmark](bench_udp_migration.nim) transfers one GB, then runs
20,000 sequential round trips each at 64 and 1,200 bytes (100 warmup RTTs first).
Both endpoints share one process on Linux loopback, pinned to CPU 0. Compiler,
flags and non-Chronos dependencies match the earlier
[full-stack comparison](udp-migration-fullstack-2026-10-22.md): Nim 2.2.6,
release/ORC, threads enabled, ERROR logging and explicit dependency paths.

Each experiment discards one warmup triple, then executes all six permutations
twice: twelve measured rounds per variant. No compilation, profiling or tests
run concurrently with measurements. CPU frequency is unlocked and the CPU is
not reserved; observations are retained even when noisy. RTT figures are medians
of per-execution percentiles. CPU time covers both endpoints and excludes setup
and cleanup, while bulk timing includes initial stream activation.

## First experiment: original stack and same-Chronos legacy control

| Metric | Original full stack | Old UDP + proposed Chronos | Integrated native API |
|---|---:|---:|---:|
| Bulk throughput (Mbit/s) | 3796.427 | 3809.231 | 3798.308 |
| CPU seconds / GB | 2.105 | 2.095 | 2.106 |
| 64-byte RTT p50 (µs) | 13.609 | 13.482 | 13.616 |
| 64-byte RTT p99 (µs) | 18.613 | 18.130 | 17.474 |
| 1,200-byte RTT p50 (µs) | 14.522 | 14.698 | 14.108 |
| 1,200-byte RTT p99 (µs) | 22.211 | 21.591 | 21.637 |

The integrated implementation's ratio of throughput medians is +0.05% versus
the original full stack and −0.29% versus the old UDP control. Median matched
changes are −0.31% and −0.46%, respectively, with four of twelve wins against
each. This run alone does not establish that a small residual cost is absent.

The original full stack is nim-lsquic `6622ec2` + resolved Chronos 4.4.0
(`55adad1`). The legacy control is the same nim-lsquic on Chronos `021d28e`.
Both are unchanged, hash-verified binaries from previous experiments.

## Second experiment: retained code versus helper inlining

Inspection found a per-packet call to native `prepareAddress`. Adding Nim's
`inline` pragma removed that call from the binary, but did not produce a
repeatable end-to-end gain. The candidate was reverted.

| Metric | Original full stack | Retained integrated API | Inline candidate, reverted |
|---|---:|---:|---:|
| Bulk throughput (Mbit/s) | 3809.383 | 3836.836 | 3824.525 |
| CPU seconds / GB | 2.100 | 2.084 | 2.091 |
| 64-byte RTT p50 (µs) | 13.700 | 13.369 | 13.062 |
| 64-byte RTT p99 (µs) | 18.910 | 17.365 | 17.852 |
| 1,200-byte RTT p50 (µs) | 14.364 | 14.288 | 13.922 |
| 1,200-byte RTT p99 (µs) | 19.773 | 19.479 | 20.888 |

The inline candidate's matched median versus the retained implementation is
+0.08%, winning seven of twelve rounds, while its ratio of throughput medians
is −0.32%. That does not justify keeping the candidate. The retained binary
has +0.72% throughput by ratio of medians versus the original and +0.77% median
matched change, with eight of twelve wins. Its binary is identical across both
experiments. The two runs together put the retained implementation close to the
original, without selecting only the more favorable run.

Latency remains workload-dependent. These sequential RTT measurements do not
establish latency under load, physical-network throughput, loss recovery,
many-connection behavior or Windows/macOS performance.

## Raw data and reproduction

[CSV](udp-migration-native-integrated-2026-10-22.csv) contains all 234 workload
records from 78 executions, including warmups. Summaries exclude `trial=0` and
pair trials within the same experiment. Counts, workloads, warmup flags and
balanced positions were validated; all executions completed their bulk-byte
and expected RTT-count checks.

[Build metadata](udp-migration-native-integrated-2026-10-22-builds.json) records
binary hashes and revisions. The integrated binary uses nim-lsquic runtime
`bb9aed9` and Chronos `7ab7b0a`; final Chronos `9815c3f` only corrects empty
non-Linux POSIX sends. Build using the earlier report's pinned compiler/paths
and separate output/cache locations. The inline candidate differs only by
`{.inline.}` on the native `prepareAddress` helper and is not retained.

Use the [experiment runner](udp-send-experiments-2026-10-22/run_experiment.py):

```sh
python3 run_experiment.py --confirmation native-integrated stack-before stack-legacy-pr native-integrated
python3 run_experiment.py --confirmation native-inline stack-before native-integrated native-inline
```

The historical [diagnostic experiments](udp-migration-send-attribution-2026-10-22.md)
remain available, but their duplicate send routines and optional raw-address
fields are not the integrated API.
