# UDP migration profiling follow-up — 2026-10-22

The profiling follow-up identified two useful receive-path changes. With both,
the final controlled comparison still shows a bulk-throughput regression:
3,822 → 3,733 Mbit/s (-2.3%), with CPU time per GB rising 2.4%. The median
paired throughput change is -1.7%. Performance parity is not established.

## Profiling and experiments

The kernel's `perf_event_paranoid=4` setting prevented hardware-counter and
`task-clock` profiling. No system setting was changed. Both implementations were
instead rebuilt with `--passC:-pg --passL:-pg`, using the original benchmark
workload and three sequential alternating old/new pairs on CPU 0. GNU gprof
aggregated the three profiles per variant. Its 10 ms user-space samples exclude
kernel CPU time, and instrumentation changes execution costs. Profile timings
were used to locate candidates, not to claim release-build speedups.

The profiles counted 2,383,683 calls to `localAddress2` in the migration versus
290,652 in the original implementation: the migration fetched the cached bound
address per packet rather than per receive turn. Address decoding (`fromSAddr`)
also doubled from 2,383,134 to 4,767,366 calls, including the added send-address
conversion. The send adapter and direct batch sender appeared in user-space
samples. Generated C additionally showed full scratch-array initialization on
every send callback.

Three release-build experiments followed. Each uses one discarded warmup triple
and six measured triples, running all six permutations of its three variants.
Each variant therefore occupies each execution position twice. The workload,
compiler, dependency versions, CPU 0 affinity and timing definitions are those
in the [original report](udp-migration-2026-10-22.md). No compilation or test
suite ran concurrently with a measured benchmark. The user reported the machine
idle; CPU frequency was not locked and CPU 0 was not reserved.

1. **Initialize only used send descriptors:** `noinit` arrays in both the adapter
   and Chronos, with complete initialization of submitted entries. Median bulk
   throughput was 3,598 Mbit/s for the unmodified migration and 3,582 Mbit/s for
   the experiment. No benefit was established, so this change was reverted.
   [Raw data](udp-migration-2026-10-22-noinit.csv).
2. **Linux `recvfrom` with `MSG_TRUNC`:** median throughput rose from 3,598 to
   3,699 Mbit/s (+2.8%) versus the unmodified migration in the same experiment.
   The original implementation reached 3,832 Mbit/s, leaving a 3.5% gap.
   [Raw data](udp-migration-2026-10-22-recvfrom.csv).
3. **Capture the bound address at socket creation:** with the receive change
   already applied, median throughput rose from 3,646 to 3,733 Mbit/s (+2.4%).
   All six paired comparisons improved; their median change was +2.7%.
   The original implementation reached 3,822 Mbit/s in this experiment.
   [Raw data](udp-migration-2026-10-22-cached.csv).

These isolated changes support receive-side overhead as a contributor. They do
not identify the cause of the remaining bulk difference. In particular, the
additional send-address conversion is still a candidate, not a measured cause.
Do not compare absolute speeds across separate experiments as if they were
simultaneous controls.

## Retained changes

Chronos uses `recvfrom(..., MSG_TRUNC)` for Linux synchronous draining. Linux
returns the actual datagram length even when the buffer is smaller, allowing
`count > buffer.len` to report `EMSGSIZE` while retaining the sender address.
The callback never receives a length beyond the buffer. This behavior is
specified by the [Linux receive manual](https://man7.org/linux/man-pages/man2/recv.2.html).
Other POSIX systems retain `recvmsg`; Windows retains its completion-based path.

nim-lsquic captures the bound local address once after constructing its transport,
before the event loop can deliver packets. Its UDP socket is not rebound or
connected during the endpoint lifetime. A failure to read the local address now
closes the transport and fails construction instead of being retried per packet.

## Final comparison

These are medians of six runs from the third experiment, comparing the original
implementation with both retained changes. RTT columns are medians of per-run
percentiles, not pooled percentiles.

| Metric | Original | Optimized migration | Change |
|---|---:|---:|---:|
| 1 GB throughput (Mbit/s) | 3821.959 | 3733.406 | -2.3% |
| 1 GB CPU time (s) | 2.092 | 2.142 | +2.4% |
| 64-byte RTT p50 (µs) | 14.018 | 13.227 | -5.6% |
| 64-byte RTT p95 (µs) | 15.521 | 14.336 | -7.6% |
| 64-byte RTT p99 (µs) | 20.505 | 16.615 | -19.0% |
| 64-byte CPU time / 20,000 RTTs (ms) | 285.521 | 269.522 | -5.6% |
| 1,200-byte RTT p50 (µs) | 14.363 | 14.023 | -2.4% |
| 1,200-byte RTT p95 (µs) | 15.766 | 15.433 | -2.1% |
| 1,200-byte RTT p99 (µs) | 19.439 | 19.071 | -1.9% |
| 1,200-byte CPU time / 20,000 RTTs (ms) | 292.305 | 288.232 | -1.4% |

The six paired throughput changes versus the original were -3.3%, -2.1%, -0.9%,
-0.5%, -1.6%, -1.8%. Latency improves in this run, but the remaining bulk gap
keeps this migration in draft. This experiment does not establish results for
physical networks, concurrent connections, latency under load, or other OSes.

## Source and reproduction details

- `old`: original nim-lsquic `6622ec2`, Chronos `2f8dd96`.
- `new`: migrated nim-lsquic `ec999b2`, Chronos `2f8dd96`.
- `noinit`: migrated code at `6b36a06`, Chronos `2fd99d7`, plus the reverted
  scratch-array experiment described above.
- `recvfrom`: migrated code at `6b36a06`, Chronos `2fd99d7` plus the Linux receive
  change retained with this report.
- `cached`: `recvfrom` plus the bound-address capture retained with this report.

The intervening nim-lsquic commits add benchmark documentation/source only;
Chronos changes between the two base revisions affect Windows truncation and
its test diagnostics, not the Linux implementation. All candidates use the
same compiler, native lsquic sources, dependencies and release flags listed in
the original report. The original and unmodified-migration binaries are reused
from the idle-machine repeat. Profiling binaries are separate from every timed
release binary.

Each raw CSV has 63 workload records, including nine records for the discarded
warmup triple (`trial=0`). Given variants A, B, C, the measured order is ABC,
ACB, BAC, BCA, CAB, CBA. The first two experiments use A=`old`, B=`new`, and
C=the named candidate. The final experiment uses A=`old`, B=`recvfrom`,
C=`cached`. Run each binary sequentially with `taskset -c 0` and the unchanged
benchmark source. Summary calculations exclude trial 0.

## Validation

- Full Linux Chronos suite: 531 tests, 517 passed, 14 skipped, no failures.
- Full Linux nim-lsquic suite: 146 tests passed, no failures.
- Direct datagram tests: all seven pass with ORC and with refc/chronosDebug,
  including exact-fit and empty packets, bounded draining, and oversized packets
  followed by valid packets with sender-address assertions for IPv4 and IPv6.
- Native cross-platform validation of the new commits remains for CI.
