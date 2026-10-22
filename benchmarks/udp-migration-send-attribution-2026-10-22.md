# Send-path attribution experiments — 2026-10-22

The bulk regression comes from adopting the new send path. Address conversion
is a demonstrated contributor: removing it improves the new sender, and adding
it slows the old sender. A borrowed native-address path recovers the measured
bulk gap while keeping the migrated receiver and Chronos batching/queue checks.

The evidence does **not** establish that descriptor size alone causes the
remaining cost. A size-only control was mixed. These experiments locate a useful
fix at the send-address representation boundary; they do not assign an exact
percentage to every copy, branch or conversion.

No experimental runtime changes are retained on either PR branch. The patches
are saved below as Linux diagnostic artifacts, not a proposed public API. The
compact candidate duplicates the send routine to isolate the experiment;
a production implementation should share its checks and platform handling.

## Method and variants

All runs use the unchanged [QUIC benchmark](bench_udp_migration.nim): one GB
bulk transfer followed by 20,000 sequential RTTs each at 64 and 1,200 bytes.
The original manual UDP path is nim-lsquic `6622ec2`; the migrated runtime is
the same as `95f7cd7`. Chronos stays at `021d28e` throughout. Nim 2.2.6,
release/ORC, native lsquic and all other dependency paths match the
[legacy control](udp-migration-legacy-control-2026-10-22.md).

Both endpoints run in one process on Linux loopback, pinned to CPU 0. Executions
are sequential. No compilation, profiling or functional tests run concurrently
with timed trials. CPU frequency is unlocked and CPU 0 is not reserved. Values
are medians of executions; matched changes pair the same trial number, and
latency values are medians of per-run percentiles.

Each screening experiment discards one warmup group, then executes every cyclic
rotation of its variant list and every reversed rotation. With four variants
this gives eight measured groups, each variant appearing twice in each position.
The padding experiment has three variants and six measured groups. Confirmation
uses all six permutations of three variants twice, giving twelve measured groups.
Each experiment's schedule was fixed before that experiment started; later
experiments were selected from earlier results. Outliers are retained.

| Variant | Change from migrated proposal |
|---|---|
| Original UDP path | Entire old nim-lsquic implementation, same proposed Chronos |
| Proposal | Current PR runtime, unchanged |
| Old sender | Restore original send implementation; keep migrated receiver |
| Budget 65 | Only change total receive budget from 64 to 65 |
| Native address | Borrow sockaddr + length in the existing descriptor; retain TransportAddress fallback |
| Old sender + conversion | Add sockaddr → TransportAddress → sockaddr to the old sender |
| Compact native address | Separate native-address descriptor and send entry point; no TransportAddress member |
| Padded native address | Same compact sender, with unused TransportAddress storage added to its descriptor |

The native paths retain Linux sendmmsg batching, the closed/queued-send checks,
EINTR retry and accepted-prefix/error handling. IPv4 destinations on mapped
IPv6 transports still take the normalization path. Payloads and addresses remain
borrowed through the synchronous call. These are not NIC/network benchmarks.

## 1. Sender versus receive budget

| Variant | Mbit/s | CPU seconds / GB |
|---|---:|---:|
| Original UDP path | 3830.784 | 2.087 |
| Proposal | 3782.991 | 2.114 |
| Old sender, migrated receiver | 3861.141 | 2.070 |
| Proposal with budget 65 | 3777.469 | 2.116 |

Restoring the old sender wins all eight matched rounds against the proposal,
with median matched improvement **2.20%**. Budget 65 wins four and loses four,
with median matched improvement **0.08%**. This points to sending rather than
the first-packet-plus-64 versus total-64 receive grouping. It does not prove
that receive grouping has no effect in every workload.

[Raw observations](udp-send-experiments-2026-10-22/send-vs-budget.csv).

## 2. Address conversion in both directions

| Variant | Mbit/s | CPU seconds / GB |
|---|---:|---:|
| Proposal | 3737.464 | 2.140 |
| Old sender | 3827.641 | 2.090 |
| Native address in existing descriptor | 3806.813 | 2.101 |
| Old sender + conversion | 3790.527 | 2.110 |

Removing conversion from the new sender wins all eight matched rounds against
the proposal, with median matched improvement **1.57%**. Adding conversion to
the old sender lowers throughput in seven of eight rounds, with median matched
change **−1.16%** relative to that old sender. This bidirectional test supports
conversion as a cause, beyond the earlier profile's doubled decode count.

The native-address variant still trails the old sender by a median matched
0.69%, with substantial variation. Do not subtract these percentages to assign
independent costs: they describe different implementations and matched pairs.

[Raw observations](udp-send-experiments-2026-10-22/address-factorial.csv).

## 3. Compact native-address path

| Variant | Mbit/s | CPU seconds / GB |
|---|---:|---:|
| Original UDP path | 3839.054 | 2.080 |
| Proposal | 3758.757 | 2.127 |
| Native address in existing descriptor | 3806.845 | 2.101 |
| Compact native address | 3840.759 | 2.082 |

The compact variant wins all eight matched rounds against the proposal, with
median matched improvement **2.32%**. Its median throughput is close to the
original UDP implementation. This motivates independent confirmation rather
than selecting the best single run.

[Raw observations](udp-send-experiments-2026-10-22/compact-address.csv).

## 4. Independent twelve-round confirmation

| Metric | Original UDP path | Proposal | Compact native address |
|---|---:|---:|---:|
| Throughput (Mbit/s) | 3826.349 | 3769.653 | 3839.769 |
| CPU seconds / GB | 2.090 | 2.119 | 2.082 |
| 64-byte RTT p50 (µs) | 13.489 | 13.258 | 13.026 |
| 64-byte RTT p95 (µs) | 14.614 | 14.116 | 14.116 |
| 64-byte RTT p99 (µs) | 17.392 | 16.655 | 16.699 |
| 1,200-byte RTT p50 (µs) | 14.191 | 14.048 | 13.840 |
| 1,200-byte RTT p95 (µs) | 15.562 | 15.515 | 15.455 |
| 1,200-byte RTT p99 (µs) | 19.300 | 21.250 | 20.337 |

Compared with the proposal, the compact path improves median throughput
**1.86%**, reduces CPU time **1.75%**, and wins eleven of twelve matched rounds.
The median matched throughput change is +1.47% (range −0.22% to +3.38%).

Compared with the original path, the ratio of throughput medians is +0.35%,
but the median matched change is −0.14%, with only five of twelve wins.
This supports recovery of the earlier systematic bulk penalty within this
experiment's variation; it does not establish that the candidate is faster
than the original or demonstrate formal equivalence. RTT medians improve,
but 1,200-byte p99 remains higher than the original in this run.

[Raw observations](udp-send-experiments-2026-10-22/send-confirmation.csv).

## 5. Descriptor size alone

| Variant | Mbit/s | CPU seconds / GB |
|---|---:|---:|
| Compact native address | 3832.091 | 2.087 |
| Same sender with unused TransportAddress storage | 3802.290 | 2.103 |
| Proposal | 3788.369 | 2.111 |

Adding unused storage lowers the ratio of throughput medians by 0.78%, but
matched results split three wins / three losses, with median matched change
−0.54% and range −3.67% to +0.93%. That does not demonstrate a repeatable
size-only penalty. The original optional-native-address variant also retains
fallback logic and different generated copies. The compact-path improvement
cannot be attributed solely to shrinking the struct based on these results.

[Raw observations](udp-send-experiments-2026-10-22/descriptor-padding.csv).

## Validation and reproduction

All 168 benchmark executions completed their exact bulk-byte and RTT-count
checks. The 504 raw workload records include warmups; summary validation checks
trial counts, warmup flags, expected workloads and balanced execution positions.
The compact candidate also passed all **146 Linux nim-lsquic tests** (88.0 s),
including partial sends, batches larger than 64 packets and dual-stack
connections. The suite was built with `-d:fast --threads:on` and the same pinned
dependency paths. Tests ran after timed benchmarks completed. The experimental
patches were restored afterward; no runtime modifications remain.

[Build metadata](udp-send-experiments-2026-10-22/builds.json) records revisions,
compiler flags, benchmark hash and every binary hash. The saved patches apply
to runtime source at nim-lsquic `95f7cd7` and Chronos `021d28e`. Apply only one
variant at a time to clean experimental checkouts; build using the pinned
paths and flags from the earlier reports, with separate compiler caches and
output binaries. Restore both checkouts between variants. These patches are
diagnostic implementations, not production-ready cross-platform additions.

- `old-send.patch`, `old-send-conversion.patch` and `budget65.patch` apply to nim-lsquic.
- `raw-address-{chronos,lsquic}.patch` apply together for the optional-native variant.
- `compact-address-{chronos,lsquic}.patch` apply together for the compact candidate.
- `padded-address-{chronos,lsquic}.patch` apply together for the size-only control.

The [runner](udp-send-experiments-2026-10-22/run_experiment.py) expects binaries
named `/tmp/udp-bench-<variant>`. Commands reproduce the saved order:

```sh
python3 run_experiment.py send-vs-budget stack-legacy-pr stack-proposal experiment-old-send experiment-budget65
python3 run_experiment.py address-factorial stack-proposal experiment-old-send experiment-raw-address experiment-old-send-conversion
python3 run_experiment.py compact-address stack-legacy-pr stack-proposal experiment-raw-address experiment-compact-address
python3 run_experiment.py --confirmation send-confirmation stack-legacy-pr stack-proposal experiment-compact-address
python3 run_experiment.py descriptor-padding experiment-compact-address experiment-padded-address stack-proposal
```

These results justify designing a native-address send boundary that avoids
mandatory decoding and re-encoding for callers such as lsquic. They do not
justify changing receive budgets or exposing the experimental duplicate routine
as-is. The production API still needs a clear borrowed-address lifetime and
length contract, shared normalization/error/queue handling, dedicated boundary
tests and native Windows/macOS validation. Both PRs remain drafts.
