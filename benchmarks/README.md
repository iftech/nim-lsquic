# nim-lsquic Benchmark Harness

Docker-based harness for measuring bandwidth and latency of nim-lsquic under
various network conditions. Runs a QUIC server and client in separate containers
connected via a Docker bridge network, with configurable latency, bandwidth
limits, packet loss, and packet reordering via `tc netem`.

## Defaults

| Parameter | CLI default | Docker Compose default |
|-----------|-------------|----------------------|
| Mode | `throughput` | `throughput` |
| Port | `14555` | `14555` |
| Upload size | 100 KB (`100000`) | 100 KB (`100000`) |
| Download size | 100 MB (`100000000`) | 10 MB (`10000000`) |
| Chunk size | 64 KB (`65536`) | 64 KB (`65536`) |
| Runs | `10` | `5` |
| Streams/conn | `4` | `4` |
| Connections | `4` | `4` |

> The Docker Compose defaults use a smaller download size and fewer runs to keep
> container-based benchmarks practical. Adjust via environment variables as needed.

## Benchmark Modes

| Mode | Connections | Streams/conn | What it measures |
|------|-------------|-------------|------------------|
| `throughput` | 1 | 1 | Baseline upload/download bandwidth |
| `latency` | 1 | 1 | Baseline RTT (ping/pong echo) |
| `multistream` | 1 | K (default: 4) | Stream contention within a single connection |
| `multiconn` | N (default: 4) | 1 | Connection contention across separate QUIC connections |
| `stress` | N (default: 4) | K (default: 4) | Combined connection + stream contention |
| `rampup` | 1 | 1 | Congestion control ramp-up: throughput over time from cold start |

### `throughput`

Opens a single connection with a single stream. The client uploads a configurable
amount of data, then the server sends back a configurable download payload. This
gives you the baseline maximum bandwidth nim-lsquic can push through one stream
with no contention. Use this to establish an upper bound before testing with
concurrent load.

### `latency`

Opens a single connection with a single stream dedicated to ping/pong. The client
sends a small 64-byte payload, the server echoes it back, and the client measures
the round-trip time. Repeats for the configured number of runs. This gives you
the baseline RTT with no competing traffic — the floor against which you compare
the other modes.

### `multistream`

Opens a single connection with K streams. K-1 streams do bulk throughput
transfers (upload + download) while 1 stream acts as a **latency probe** running
the same ping/pong as the `latency` mode. All streams share the same QUIC
connection, meaning they share one congestion window, one flow control context,
and one `engine_process` call. This answers the question: *does bulk traffic on
other streams within the same connection degrade latency?* If the latency probe
p50/p95 increases significantly compared to the `latency` baseline, it points to
stream-level contention inside lsquic (stream scheduling, flow control
head-of-line blocking, or engine processing overhead).

### `multiconn`

Opens N separate QUIC connections, each with a single stream. N-1 connections do
bulk throughput transfers while 1 connection runs the latency probe. Each
connection gets its own congestion state, but on the server side they still share
the same UDP socket and the same lsquic engine (one `engine_process` call handles
all connections). This answers: *does load from other connections degrade latency
on a separate connection?* Degradation here points to server-side engine
contention or UDP socket bottlenecks rather than stream-level issues.

### `stress`

The most realistic scenario. Opens N connections with K streams each. On every
connection, K-1 streams do bulk transfers and 1 stream runs the latency probe.
This combines the contention from both `multistream` and `multiconn` — stream
scheduling pressure within each connection, plus engine-level pressure across
connections. Compare the latency probe results against the `latency`, `multistream`,
and `multiconn` baselines to isolate where degradation comes from.

### `rampup`

Opens a single connection with a single stream and starts a large download.
Instead of reporting a single aggregate throughput number, it samples throughput
in 50ms time windows and plots how bandwidth evolves from the start. This shows
CUBIC slow-start behavior: how quickly the congestion window grows, how long it
takes to reach steady state, and whether the connection fully utilizes the
available bandwidth.

The key metric is **time to 90% of peak throughput** — the point where
slow-start has essentially finished. Under high-latency or lossy conditions, this
ramp-up time grows significantly because CUBIC's window growth depends on RTT.
Compare across network scenarios to see how network conditions affect convergence
time.

Example output (100MB download over WAN with 25ms latency, 100 Mbit cap):

```
Stream #1 [ramp-up] (192 windows, 50ms each):
  Time to 90% peak: 150.000ms
  Peak throughput:  95.77 Mbit/s
  Timeline:
       50ms |     7.2 Mbit/s | ###
      100ms |    51.0 Mbit/s | #####################
      150ms |    94.6 Mbit/s | ########################################
      200ms |    94.9 Mbit/s | ########################################
      ...
```

## Network Scenarios

The matrix runner (`run.sh`) tests across these predefined network conditions
(all 6 used in full mode, only `lan` in `--quick` mode):

| Scenario | Latency | Bandwidth | Packet Loss | Reorder |
|----------|---------|-----------|-------------|---------|
| `lan` | 0ms | unlimited | 0% | 0% |
| `wan` | 25ms | 100 Mbit | 0% | 0% |
| `constrained` | 50ms | 10 Mbit | 0.1% | 0% |
| `lossy` | 25ms | 50 Mbit | 2% | 0% |
| `mobile` | 75ms | 5 Mbit | 1% | 0% |
| `reorder` | 25ms | 100 Mbit | 0% | 25% |

### `run.sh` Matrix Defaults

**Full mode** (`./benchmarks/run.sh`):

| Mode | Runs | Streams | Connections | Upload | Download |
|------|------|---------|-------------|--------|----------|
| `throughput` | 5 | 1 | 1 | 100 KB | 10 MB |
| `latency` | 100 | 1 | 1 | — | — |
| `multistream` | 2 | 4 | 1 | 100 KB | 10 MB |
| `multiconn` | 2 | 1 | 4 | 100 KB | 10 MB |
| `stress` | 1 | 4 | 4 | 100 KB | 10 MB |
| `rampup` | 1 | 1 | 1 | — | 100 MB |

**Quick mode** (`./benchmarks/run.sh --quick`) — LAN scenario only:

| Mode | Runs | Streams | Connections | Upload | Download |
|------|------|---------|-------------|--------|----------|
| `throughput` | 3 | 1 | 1 | 100 KB | 1 MB |
| `latency` | 20 | 1 | 1 | — | — |
| `multistream` | 1 | 4 | 1 | 100 KB | 1 MB |
| `multiconn` | 1 | 1 | 3 | 100 KB | 1 MB |
| `stress` | 1 | 3 | 3 | 100 KB | 1 MB |
| `rampup` | 1 | 1 | 1 | — | 10 MB |

## Prerequisites

- Docker (with Compose V2)
- `NET_ADMIN` capability (needed for `tc netem` inside containers)

## Quick Start

```bash
# Run the full matrix (6 scenarios x 6 modes = 36 benchmarks)
./benchmarks/run.sh

# Quick mode: LAN only, smaller payloads, fewer runs
./benchmarks/run.sh --quick

# Single scenario or mode
./benchmarks/run.sh --scenario wan --mode latency

# Skip Docker image rebuild (if already built)
./benchmarks/run.sh --quick --no-build
```

## Direct Docker Compose Usage

For more control, run Docker Compose directly with environment variables:

```bash
# Throughput test with 50ms latency and 10Mbit bandwidth cap
BENCH_MODE=throughput BENCH_RUNS=5 \
BENCH_UPLOAD_SIZE=100000 BENCH_DOWNLOAD_SIZE=10000000 \
LATENCY_MS=50 BANDWIDTH_MBIT=10 \
  docker compose -f benchmarks/docker-compose.yml up \
    --abort-on-container-exit --exit-code-from bench-client

# Stress test: 8 connections x 8 streams, lossy network
BENCH_MODE=stress BENCH_CONNECTIONS=8 BENCH_STREAMS=8 \
LATENCY_MS=25 PACKET_LOSS_PCT=2 BANDWIDTH_MBIT=50 \
  docker compose -f benchmarks/docker-compose.yml up \
    --abort-on-container-exit --exit-code-from bench-client

# Clean up after
docker compose -f benchmarks/docker-compose.yml down --remove-orphans
```

### Environment Variables

**Benchmark parameters:**

| Variable | Default | Description |
|----------|---------|-------------|
| `BENCH_MODE` | `throughput` | Benchmark mode |
| `BENCH_RUNS` | `5` | Number of iterations |
| `BENCH_CONNECTIONS` | `4` | Number of QUIC connections (multiconn/stress) |
| `BENCH_STREAMS` | `4` | Streams per connection (multistream/stress) |
| `BENCH_UPLOAD_SIZE` | `100000` | Bytes to upload per stream (100 KB) |
| `BENCH_DOWNLOAD_SIZE` | `10000000` | Bytes to download per stream (10 MB) |
| `BENCH_CHUNK_SIZE` | `65536` | I/O chunk size (64 KB) |

**Network shaping (applied on client side):**

| Variable | Default | Description |
|----------|---------|-------------|
| `LATENCY_MS` | `0` | One-way delay in milliseconds |
| `BANDWIDTH_MBIT` | `0` | Bandwidth limit in Mbit/s (0 = unlimited) |
| `PACKET_LOSS_PCT` | `0` | Packet loss percentage |
| `JITTER_MS` | `0` | Delay jitter in milliseconds |
| `REORDER_PCT` | `0` | Packet reorder percentage (requires `LATENCY_MS` > 0) |

## Running Locally (Without Docker)

You can compile and run the benchmarks directly for loopback testing:

```bash
# Compile
nim c --threads:on -d:release --out:benchmarks/bench_server benchmarks/bench_server.nim
nim c --threads:on -d:release --out:benchmarks/bench_client benchmarks/bench_client.nim

# Run server in background
./benchmarks/bench_server --port 14555 &

# Run client
./benchmarks/bench_client --mode stress --server 127.0.0.1 --port 14555 \
  --connections 4 --streams 4 --runs 3 --json

# Kill server when done
kill %1
```

### Server CLI Options

```
--listen, -l       Listen address (default: 0.0.0.0)
--port, -p         Port (default: 14555)
```

### Client CLI Options

```
--mode, -m         Benchmark mode (default: throughput)
                   Options: throughput|latency|multistream|multiconn|stress|rampup
--server, -s       Server address (default: 127.0.0.1)
--port, -p         Server port (default: 14555)
--upload-size      Bytes to upload per stream (default: 100000 = 100 KB)
--download-size    Bytes to download per stream (default: 100000000 = 100 MB)
--chunk-size       I/O chunk size (default: 65536 = 64 KB)
--runs, -r         Number of iterations (default: 10)
--streams, -k      Streams per connection (default: 4)
--connections, -n  Number of connections (default: 4)
--json             Output results as JSON (default: human-readable)
```

## Output

### Sample Run

Full matrix run (`./benchmarks/run.sh`) across all 6 scenarios and 6 modes.

Measured on an Intel Core Ultra 7 155H (22 threads), 62 GB RAM, Docker bridge
networking. Absolute numbers are host-dependent — especially the LAN row, which
measures loopback-class bandwidth rather than a real network — so compare
relative movements between modes rather than treating these as targets.

The `Lat p95` values below are a **single draw from a wide distribution**, not
repeatable figures: re-running an unchanged build moves them by up to 3x. See
[Reading the tail](#reading-the-tail) before comparing any of them against a run
of your own.

```
Scenario        Mode           Conns  Strms  Upload          Download        Lat p50      Lat p95      Stalls       Duration     CPU cli     CPU srv     Peak RSS
========================================================================================================================================================================
lan             throughput     1      1      22.49 Mbit/s    2.25 Gbit/s     -            -            -            177.895ms    144.961ms   289.813ms   11.8 MiB
lan             latency        1      1      -               -               55.313us     87.729us     0/0/0        6.566ms      33.146ms    111.565ms   11.7 MiB
lan             multistream    1      4      18.82 Mbit/s    1.88 Gbit/s     40.992us     17.191ms     0/0/0        255.111ms    189.392ms   380.229ms   21.7 MiB
lan             multiconn      4      1      20.15 Mbit/s    2.01 Gbit/s     39.526us     16.246ms     0/0/0        238.226ms    186.240ms   384.302ms   21.4 MiB
lan             stress         4      4      21.47 Mbit/s    2.15 Gbit/s     51.891us     53.027ms     0/0/0        447.053ms    309.429ms   613.795ms   59.3 MiB
lan             rampup         1      1      -               2.40 Gbit/s     150.000ms    p90          -            333.699ms    252.956ms   461.795ms   11.8 MiB
wan             throughput     1      1      902.85 Kbit/s   90.28 Mbit/s    -            -            -            4.430s       746.879ms   4.393s      12.3 MiB
wan             latency        1      1      -               -               25.352ms     25.475ms     0/0/0        2.535s       49.213ms    203.719ms   11.9 MiB
wan             multistream    1      4      637.13 Kbit/s   63.71 Mbit/s    25.376ms     220.711ms    20/0/0       7.534s       818.990ms   5.326s      15.5 MiB
wan             multiconn      4      1      919.43 Kbit/s   91.94 Mbit/s    36.339ms     36.378ms     0/0/0        5.221s       828.930ms   5.299s      16.0 MiB
wan             stress         4      4      591.71 Kbit/s   59.17 Mbit/s    25.770ms     1.172s       40/11/0      16.224s      1.401s      10.593s     30.5 MiB
wan             rampup         1      1      -               83.57 Mbit/s    150.000ms    p90          -            9.573s       1.137s      8.688s      16.5 MiB
constrained     throughput     1      1      93.39 Kbit/s    9.34 Mbit/s     -            -            -            42.833s      1.077s      1.987s      11.8 MiB
constrained     latency        1      1      -               -               50.466ms     50.669ms     0/0/0        5.050s       60.147ms    274.517ms   11.7 MiB
constrained     multistream    1      4      94.29 Kbit/s    9.43 Mbit/s     96.614ms     428.695ms    34/2/2       50.905s      1.718s      2.646s      11.7 MiB
constrained     multiconn      4      1      93.59 Kbit/s    9.36 Mbit/s     95.801ms     100.843ms    15/0/0       51.288s      1.722s      2.911s      11.8 MiB
constrained     stress         4      4      92.38 Kbit/s    9.24 Mbit/s     50.383ms     109.086ms    11/5/4       103.914s     3.364s      5.666s      12.3 MiB
constrained     rampup         1      1      -               9.49 Mbit/s     700.000ms    p90          -            84.307s      2.549s      3.914s      11.6 MiB
lossy           throughput     1      1      406.78 Kbit/s   40.68 Mbit/s    -            -            -            9.833s       718.467ms   8.570s      11.7 MiB
lossy           latency        1      1      -               -               25.364ms     25.630ms     1/0/0        2.672s       57.357ms    174.575ms   11.6 MiB
lossy           multistream    1      4      361.71 Kbit/s   36.17 Mbit/s    25.374ms     565.669ms    17/3/0       13.270s      804.105ms   10.357s     13.4 MiB
lossy           multiconn      4      1      343.65 Kbit/s   34.36 Mbit/s    47.499ms     47.627ms     1/0/0        13.968s      862.115ms   10.488s     15.8 MiB
lossy           stress         4      4      301.73 Kbit/s   30.17 Mbit/s    25.336ms     1.648s       34/11/3      31.816s      1.405s      21.058s     26.4 MiB
lossy           rampup         1      1      -               38.98 Mbit/s    150.000ms    p90          -            20.523s      1.198s      17.174s     12.9 MiB
mobile          throughput     1      1      45.32 Kbit/s    4.53 Mbit/s     -            -            -            88.264s      1.361s      3.604s      11.9 MiB
mobile          latency        1      1      -               -               75.613ms     75.801ms     0/0/0        7.567s       56.898ms    316.761ms   11.6 MiB
mobile          multistream    1      4      46.86 Kbit/s    4.69 Mbit/s     121.086ms    770.688ms    95/3/2       102.422s     1.757s      4.297s      11.7 MiB
mobile          multiconn      4      1      46.53 Kbit/s    4.65 Mbit/s     118.931ms    126.222ms    88/0/0       103.161s     1.800s      4.324s      11.9 MiB
mobile          stress         4      4      46.34 Kbit/s    4.63 Mbit/s     75.551ms     239.780ms    21/6/4       207.150s     3.922s      8.926s      13.0 MiB
mobile          rampup         1      1      -               4.75 Mbit/s     8.250s       p90          -            168.595s     2.640s      6.899s      11.7 MiB
reorder         throughput     1      1      782.97 Kbit/s   78.30 Mbit/s    -            -            -            5.109s       610.448ms   4.411s      13.0 MiB
reorder         latency        1      1      -               -               25.332ms     25.439ms     0/0/0        2.057s       47.919ms    209.847ms   11.5 MiB
reorder         multistream    1      4      617.32 Kbit/s   61.73 Mbit/s    25.360ms     620.952ms    13/2/0       7.776s       622.010ms   5.293s      15.1 MiB
reorder         multiconn      4      1      677.75 Kbit/s   67.77 Mbit/s    36.279ms     36.373ms     0/0/0        7.082s       660.459ms   5.290s      14.8 MiB
reorder         stress         4      4      573.57 Kbit/s   57.36 Mbit/s    31.518ms     727.092ms    37/6/1       16.737s      1.284s      10.614s     24.6 MiB
reorder         rampup         1      1      -               94.26 Mbit/s    150.000ms    p90          -            8.487s       971.235ms   8.753s      12.0 MiB
```

The three trailing columns are:

- **CPU cli** — user + system CPU consumed by the client process, from
  `getrusage(RUSAGE_SELF)`. This is wall-clock time across all cores, not
  fraction of one core: 1 s here on a run that took 500 ms wall-clock means the
  process kept roughly two cores busy for the duration.
- **CPU srv** — total CPU consumed by the server container, read from
  `/sys/fs/cgroup/cpu.stat` (cgroup v2) while the container is still alive.
  Covers the whole cgroup, so it is not strictly comparable to `getrusage`, but
  the delta between two runs of the same server binary is meaningful.
- **Peak RSS** — larger of the two containers' peak resident set. Includes the
  Nim runtime and lsquic engine state.

`CPU srv` matters because much of the QUIC send path (engine tick coalescing,
packet-out scheduling, retransmission) runs on the server side of a benchmark
that measures download throughput, so client CPU alone would miss most of the
send-path cost.

#### Reading the results

**Columns:**

- **Scenario** — network condition profile applied via `tc netem` (see
  [Network Scenarios](#network-scenarios) above for the exact latency, bandwidth,
  and loss values each name maps to)
- **Mode** — benchmark mode that was run
- **Conns** — number of QUIC connections used
- **Strms** — number of streams per connection
- **Upload** — aggregate upload throughput across all streams, computed as total
  bytes uploaded divided by total wall-clock duration. Shows `-` for latency-only
  modes where no bulk data is transferred. Note: in throughput mode the upload is
  small relative to the download, so this number reflects the fraction of time
  spent uploading rather than burst upload speed.
- **Download** — same as Upload but for the download direction
- **Lat p50** — median (50th percentile) round-trip time from the latency probe
  stream. This is the RTT of a small ping/pong echo measured alongside any bulk
  transfers. Shows `-` for pure throughput mode which has no latency probe.
  For `rampup` mode, this column shows the **time to 90% of peak throughput**
  instead (labeled `p90` in the Lat p95 column).
- **Lat p95** — 95th percentile RTT. Shows `p90` for `rampup` mode to indicate
  the Lat p50 column contains the time-to-90%-peak metric. **Not stable enough to
  compare between runs on shaped scenarios** — see [Reading the
  tail](#reading-the-tail) below, and use the Stalls column instead.
- **Stalls** — how many latency samples exceeded 100 ms / 1 s / 10 s, e.g.
  `34/11/3`. This is the tail metric to compare across runs. Shows `-` for modes
  with no latency probe.
- **Duration** — total wall-clock time for the entire benchmark run (all
  iterations, all streams)

#### Reading the tail

**Do not compare p95 or p99 between runs on shaped scenarios.** They are not
stable enough to carry a regression signal, and reading them as if they were has
produced wrong verdicts on real PRs.

The numbers below are 8 consecutive runs of the *same cell* on *unchanged code*,
back to back on an idle machine:

| cell | metric | 8 runs on identical code | spread |
|---|---|---|---|
| `wan_multistream` | p50 | 25.20 – 25.33 ms | 1.01x |
| `wan_multistream` | p95 | 220.8 – 649.7 ms | **2.94x** |
| `wan_multistream` | p99 | 764 – 4263 ms | **5.58x** |
| `lossy_stress` | p95 | 896 – 1972 ms | **2.20x** |
| `lossy_stress` | p99 | 10.1 – 25.0 s | **2.46x** |

Two things cause this:

1. **Sample count.** `multistream` and `multiconn` collect 100 latency samples
   per cell, `stress` 200. At n=100, p95 is the 5th-worst observation and p99 is
   essentially the single worst.
2. **The tail is quantized.** Under loss, samples pile up on the rungs of
   lsquic's exponential retransmission backoff — roughly 1 s, 6 s, 12 s, 25 s,
   50 s. A percentile reports *which rung one sample happened to land on*, so it
   jumps between discrete values rather than moving smoothly. Raising the sample
   count does not fix this; it only changes which sample gets indexed.

The **Stalls** column exists because of this. Counting samples above fixed
thresholds aggregates the whole tail instead of indexing into it, and it is
stable across the same runs at no extra wall time:

| cell | metric | 8 runs on identical code | stdev |
|---|---|---|---|
| `lossy_stress` | stalls > 1 s | 9, 10, 9, 10, 11, 10, 11, 13 | **1.3** |
| `lossy_stress` | stalls > 10 s | 3, 3, 2, 2, 3, 2, 4, 2 | **0.7** |
| `wan_multistream` | stalls > 100 ms | 17, 14, 16, 16, 16, 14, 15, 13 | **1.4** |

Which threshold carries the signal depends on the shaping: `wan_multistream`
never stalls past 1 s, so only the first bucket is informative there, while
`lossy_stress` routinely stalls past 10 s and its first bucket is the noisy one.
Read the bucket that is non-zero and not saturated for the cell in question.

**What to trust when comparing two builds:**

- **Reliable** — `errors` (categorical, and the signal that caught the GSO/USO
  regression in #115), Lat p50, Stalls, CPU, Peak RSS.
- **Use with care** — Download/Upload. Stable on LAN and bandwidth-capped
  scenarios, but on `lossy_stress` throughput itself has a 25% coefficient of
  variation, so a sub-30% throughput move there means nothing on its own.
- **Do not use** — Lat p95, and p99 computed from the JSON. Also `rampup`
  entirely: it is `runs=1`, a single sub-second transfer with no repetition, and
  it has been observed to span 1546 – 2832 Mbit/s on the same commit.

If a percentile move is the only evidence you have for a regression, it is not
evidence. Re-run the cell 8 times on the unmodified base commit and compare the
distributions before drawing a conclusion.

#### Analysis by scenario

**LAN** (no shaping) — establishes the upper bound, and it is the only scenario
where nim-lsquic itself, rather than the emulated link, is the bottleneck.
Single-stream download reaches 2.25 Gbit/s on the Docker bridge. Parallel streams
and connections stay in the same 1.9-2.4 Gbit/s band; extra streams and
connections do not increase aggregate throughput here, indicating that a single
stream already saturates the engine at LAN speeds. Latency starts at 55 µs p50
and stays at microsecond-scale medians across all modes; p95 grows from 88 µs
(baseline) to 53 ms under stress, showing the cost of engine processing
contention across 16 concurrent streams.

**WAN** (25 ms, 100 Mbit) — throughput reaches 90.3 Mbit/s, ~90% of the 100 Mbit
cap. CUBIC needs multiple RTTs to grow the congestion window and each of the 5
sequential runs starts cold. Latency baseline is 25.4 ms, matching the netem
delay exactly. Under `multiconn` the probe latency rises to 36.3 ms (+11 ms),
pointing to engine-level contention across connections. `stress` p95 hits 1.17 s
from head-of-line blocking cascades across 16 concurrent streams. Rampup takes
150 ms (6 RTTs) to reach 90% of peak.

**Constrained** (50 ms, 10 Mbit, 0.1% loss) — all modes saturate at ~9.2-9.4
Mbit/s, confirming the 10 Mbit link is the bottleneck rather than the engine.
Contention modes show nearly identical throughput because there is no bandwidth
left to fight over. The main effect of contention is on latency: `multistream`
p95 reaches 429 ms, while `stress` p95 sits lower at 109 ms. Rampup takes 700 ms
(14 RTTs at 50 ms) to reach steady state, consistent with CUBIC slow-start
behavior.

**Lossy** (25 ms, 50 Mbit, 2% loss) — the most punishing scenario for tail
latency. Single-stream throughput reaches 40.7 Mbit/s (81% of cap) because 2%
loss causes frequent congestion-window reductions. Baseline latency p50 is 25.4
ms, matching the netem delay, with p95 at 25.6 ms. `stress` p95 reaches 1.65 s
as loss and congestion combine into retransmission cascades across 16 concurrent
streams — the worst tail in the matrix.

**Mobile** (75 ms, 5 Mbit, 1% loss) — throughput settles at 4.53 Mbit/s (91% of
cap). The tight bandwidth means contention modes show nearly identical
throughput (~4.6-4.7 Mbit/s) since the link is fully saturated regardless. The
contention effect shows up in latency instead: `multistream` p95 reaches 771 ms
from within-connection scheduling pressure under the narrow pipe. Rampup takes
8.25 s to converge — much longer than expected from RTT alone, because loss
events during slow-start force repeated window reductions on this narrow, lossy
link.

**Reorder** (25 ms, 100 Mbit, 25% reorder) — single-stream throughput reaches
78.3 Mbit/s, below the 100 Mbit cap but above the `lossy` figure despite
carrying 25% reordering. Reordered packets trigger duplicate ACKs that CUBIC
interprets as loss and shrink the congestion window, but the packets themselves
eventually arrive, so there is no retransmission cost. Rampup fully recovers to
the 100 Mbit cap (peak 94.3 Mbit/s), unlike the sequential-run cold-start
average.

#### Key takeaways

- **Bandwidth caps are enforced bidirectionally** — download throughput stays
  below the configured cap in all scenarios (shaping is applied on both client
  and server egress via `tc netem`).
- **Latency baselines match netem delays exactly** — 25.3-25.4 ms for
  WAN/lossy/reorder (25 ms configured), 50.5 ms for constrained (50 ms), 75.6 ms
  for mobile (75 ms). p50 latency is unchanged across all contention modes; the
  cost of contention appears entirely in the tail.
- **Contention degrades latency, not throughput** — under
  constrained/mobile/lossy the link is fully saturated regardless of mode, but
  p95 latency grows 2-20x from the baseline latency once other streams share
  the connection.
- **Loss and reordering hurt in different places** — 2% loss (`lossy`) drops
  single-stream throughput to 81% of cap and drives `stress` p95 to 1.65 s,
  while 25% reorder yields 78% of cap and a `stress` p95 of 727 ms. Lost packets
  need real retransmission and RTO backoff; reordered packets just trigger
  spurious duplicate ACKs. The two scenarios have different caps (50 vs 100
  Mbit), so compare percentages rather than absolute Mbit/s.
- **`multiconn` beats `multistream` for latency-sensitive workloads** — putting
  the latency probe on its own connection (`multiconn`, p95 36-127 ms across
  scenarios) instead of sharing one with bulk streams (`multistream`, p95
  221-771 ms) reduces the p95 tail by 3-10x. Independent congestion state per
  connection isolates the probe from bulk head-of-line blocking.
- **CUBIC ramp-up scales with RTT and loss** — time-to-90% grows from 150 ms
  (LAN/WAN) to 700 ms (50 ms RTT, 0.1% loss) to 8.25 s (75 ms RTT + 1% loss),
  with loss events during slow-start significantly extending convergence on
  narrow, lossy links.

### Human-Readable Output

Without `--json`, the client prints a detailed breakdown:

```
=== Benchmark Results ===
Mode: stress
Connections: 3, Streams/conn: 3
Total duration: 11.079ms

  Connection #1:
    Stream #1 [throughput]:
      Upload:   10000 bytes -> 41.39 Mbit/s
      Download: 50000 bytes -> 206.96 Mbit/s
      Duration: 1.933ms
    Stream #2 [throughput]:
      Upload:   10000 bytes -> 19.48 Mbit/s
      Download: 50000 bytes -> 97.38 Mbit/s
      Duration: 4.108ms
    Stream #3 [latency] (50 samples):
      Mean:  213.898us
      p50:   90.164us
      p95:   456.471us
      p99:   801.782us
      Min:   51.400us
      Max:   3.967ms
  Connection #2:
    ...

  Client resource usage:
    CPU user: 16.461ms
    CPU sys:  3.713ms
    Peak RSS: 8.4 MiB
```

### JSON Output

With `--json`, the client outputs machine-readable JSON with per-stream latency
samples (in nanoseconds) for further analysis:

```json
{
  "mode": "latency",
  "connections": 1,
  "streams_per_conn": 1,
  "duration_ns": 2535000000,
  "connections_results": [
    {
      "streams": [
        {
          "upload_bytes": 0,
          "download_bytes": 0,
          "duration_ns": 2534900000,
          "latency_samples_ns": [25352000, 25401000, 25311000, ...]
        }
      ],
      "duration_ns": 2535000000
    }
  ],
  "errors": [],
  "client_cpu_user_ns": 33502000,
  "client_cpu_sys_ns": 15711000,
  "client_max_rss_bytes": 12443648,
  "server_cpu_ns": 203719000,
  "server_cpu_user_ns": 150710000,
  "server_cpu_sys_ns": 53008000,
  "server_max_rss_bytes": 5595136
}
```

The `errors` array lists any streams that failed transport-level (`StreamError`,
`ConnectionError`, etc.) during the run - the benchmark records them and keeps
going rather than aborting. Server-side CPU is read from the container's cgroup;
client-side CPU and RSS come from `getrusage(RUSAGE_SELF)`.

## How It Works

1. **Server** listens for QUIC connections and handles two stream protocols:
   - **Throughput** (type `0x01`): reads upload data, sends back requested download size
   - **Latency** (type `0x02`): echoes length-prefixed payloads back immediately

2. **Client** opens connections/streams based on the selected mode. In multi-stream
   and multi-connection modes, it runs bulk transfers alongside a latency probe
   to measure contention effects.

3. **Network shaping** is applied via `tc netem` in the Docker entrypoint (requires
   `NET_ADMIN` capability). Since `tc qdisc` only shapes egress (outbound) traffic,
   bandwidth limits are applied on **both** the client and server sides so that
   uploads and downloads are both capped. Latency, packet loss, and reordering are
   applied on the client side only to avoid doubling the delay.

4. **Results** are collected as JSON per run and aggregated into a summary table
   by `run.sh`.
