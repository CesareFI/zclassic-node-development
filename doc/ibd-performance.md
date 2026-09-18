# Full-validation IBD measurements

The objective is faster synchronization of the existing Zclassic chain with
unchanged consensus validation. Snapshot import, assumed chainstate, skipped
proof checks, and changes to consensus constants are outside this work.

## Reproducing a fresh-node run

Build the daemon using `BUILD.md`, install the hash-verified Zcash parameters,
then run (Python 3.11 or later):

```sh
python3 qa/zcash/benchmark-ibd.py \
  --daemon ./src/zclassicd \
  --datadir /tmp/zclassic-ibd-baseline-01 \
  --seconds 180 > /tmp/zclassic-ibd-baseline-01.jsonl
```

The datadir must not exist. The tool never erases data, imports a snapshot,
changes verification flags, or opens a wallet. RPC is bound to loopback and uses
the daemon's random cookie; the cookie is not recorded in results. Each run ends
with SIGTERM and waits for clean shutdown. A shutdown that takes more than two
minutes is reported and left running, rather than killed while writing its DB.

Use a different datadir for each run. `--connect=host:port` can be repeated to
hold the ordinary P2P peers constant between runs. Without it, use normal peer
discovery. Keep binaries, durations, peer selection, hardware, and background
load recorded. Alternate baseline and candidate runs; public-network runs have
uncontrolled peer and bandwidth variation. Parameter and OS caches affect
startup timings, so distinguish the first run from subsequent warm runs.

The JSONL stream records:

- Binary SHA-256, daemon arguments, start time, and elapsed time.
- Observed time to first peer, accepted header, and accepted block.
- Header/block rates, network bytes, and receive MB/s (decimal MB).
- Peer count, peers with outstanding blocks, total in-flight blocks, and repeated
  in-flight heights. Repeated heights are diagnostic, not proof of duplicate
  hashes: peers may advertise different forks at the same height.
- Linux process CPU seconds, RSS, physical disk bytes, and read/write syscall
  counts. Syscall counts are **not** device IOPS. Cache hits do not count as
  physical reads; delayed writeback can outlive a sample.
- RPC-unavailable samples, clean-shutdown elapsed time, last sampled block hash,
  logged request counts and timeout counts.

Peer and progress observations have approximately one sample interval of timing
uncertainty, plus RPC latency. Debug-log event timestamps have one-second
resolution. The three RPC calls in a sample are not atomic. Debug networking
logs add measurement overhead; use the same settings on both binaries. Keep
raw logs, JSONL output, datadirs, cryptographic parameters, and binaries outside
Git. Commit only the tool and an honest summary of results and limitations.

## Initial environment inspection (2026-09-18)

The available checkout started at `f6bf5a52b` on the clean
`diagnostic/checkblock-beta6-20260912` branch. No running legacy daemon or prior
IBD measurement series was found. Development continues on
`dev/ibd-performance-20260918`, preserving that diagnostic change.

The previous local build could compile C++ but could not link `-lrustzcash`.
The dependency was rebuilt from the repository-pinned Rust 1.32.0 toolchain,
crate hashes, and librustzcash commit. All five runtime parameter files were
downloaded from `https://download.z.cash/downloads/` and verified against the
repository's recorded SHA-256 hashes. No verification stubs are used.

For this existing native build, the dependency and link commands were:

```sh
make -C depends librustzcash -j4
mkdir -p /tmp/zclassic-ibd-rust
for archive in depends/built/x86_64-unknown-linux-gnu/librustzcash*/*.tar.gz; do
  tar -xf "$archive" -C /tmp/zclassic-ibd-rust
done
make -C src -j8 zclassicd zclassic-cli zcash-gtest test/test_bitcoin \
  LDFLAGS=-L/tmp/zclassic-ibd-rust/lib CXX='g++ -std=c++14'
```

C++14 supports the host's newer GoogleTest headers; no consensus code is changed
by this language-mode choice. This supplements the existing configured native
build; it is not a replacement for the clean-build instructions in `BUILD.md`.

No IBD speedup is claimed from environment repair or measurement tooling.

## Single-chunk Sprout verification (2026-09-18)

An 8-second `perf` profile during full-validation mainnet IBD attributed 88.44%
of sampled cycles to two OpenMP runtime locations. The verifier's sparse-vector
accumulation passes `chunks = 1` to `multi_exp`, but both algorithm branches
started an OpenMP team for that single loop iteration. This host exposes 48
logical CPUs. The change adds `if(chunks > 1)` to those two parallel directives.
It preserves every scalar multiplication, addition, reduction, proof check,
input, and result; it changes only whether idle workers are started.

### Measurements

All node runs use fresh datadirs, normal header/block validation, the default
cache and txindex settings, and the same benchmark logging. Parameter files
and OS page cache are warm. Initial runs overlapped build/test activity; these
are development measurements on a shared host, not a dedicated performance lab.

| Workload | Baseline | Candidate |
| --- | ---: | ---: |
| Public mainnet, blocks at ~180 s | 5,146 | 5,537 |
| Public mainnet, headers at ~180 s | 5,440 | 5,760 |
| Public mainnet, CPU seconds | 3,300.01 | 164.06 |
| Local replay, time to validate height 5,000 | 167.14 s | 143.11 s |
| Local replay, CPU seconds | 2,902.56 | 145.31 |
| Local replay, final sampled RSS | 90.93 MiB | 93.93 MiB |
| Local replay, bytes received | 27,783,019 | 27,783,019 |
| Local replay, block requests | 5,000 | 5,000 |

The first controlled replay reduced time to the same validated height by 14.4%
and CPU consumption by 95.0%. Both nodes reached exactly
`00000009e2d42216b8eb5a4ccdd08cd1f49019137d5daa899bd2bc137cedf416`,
had zero in-flight blocks at completion, and shut down cleanly. Neither run
logged a block timeout or stall disconnect, or sampled repeated in-flight
heights. These are first-5,000-block results, not total-chain IBD results. Public
peer timing varied substantially; the public block-count difference alone is
not a controlled estimate of speedup. RSS and disk writes did not improve.

A synthetic 100-operation single-chunk benchmark independently compared every
result to a scalar-multiplication sum:

| OpenMP maximum threads | Baseline wall / CPU seconds | Candidate wall / CPU seconds |
| --- | ---: | ---: |
| 1 | 0.01633 / 0.01631 | 0.01632 / 0.01630 |
| 4 | 0.01662 / 0.06485 | 0.01647 / 0.01647 |
| 48 | 0.63788 / 28.3458 | 0.01627 / 0.01623 |

This synthetic workload isolates worker overhead; it does not predict whole
chain throughput. The largest benefit is on machines with many CPU cores.

### Reproducing the controlled replay

After a scratch mainnet node has validated more than 5,000 blocks and shut down,
start the fixture server in another terminal:

```sh
python3 qa/zcash/ibd-local-replay.py \
  --blocks /tmp/zclassic-ibd-baseline-01/blocks --height 5000
```

It serves an immutable prefix of ordinary historical headers and blocks on
loopback only. It is not a validating node. Each benchmark daemon independently
validates those bytes using its unchanged mainnet validation path:

```sh
python3 qa/zcash/benchmark-ibd.py \
  --daemon /path/to/baseline/zclassicd \
  --datadir /tmp/zclassic-replay-before \
  --seconds 300 --stop-height 5000 --connect 127.0.0.1:18444 \
  > /tmp/zclassic-replay-before.jsonl
# Repeat with the candidate binary and a new datadir; compare final hashes too.
```

The fixture checks framing and rejects captures containing forks. Use a stopped,
short-lived scratch capture. It keeps block locations and headers in memory and
reads block bodies on demand; never point it at a production datadir in use.

Build the isolated arithmetic benchmark against each checkout's headers and
existing libsnark archive:

```sh
g++ -std=c++11 -O2 -Wall -Wextra -Wno-unused-parameter \
  -DMULTICORE -fopenmp -DCURVE_ALT_BN128 \
  -Isrc/snark -Isrc/snark/libsnark qa/zcash/benchmark-multiexp.cpp \
  src/snark/libsnark.a -lgmpxx -lgmp -lsodium -o /tmp/benchmark-multiexp
OMP_NUM_THREADS=48 /tmp/benchmark-multiexp 100
```

### Validation

- Baseline: 174/174 GoogleTests; 372/372 Boost tests with 142,740,261 assertions.
- Candidate: 175/175 GoogleTests, including actual valid/invalid proof cases and
  new G1/G2 equivalence coverage for empty inputs, identity points, zero scalars,
  uneven partitions, single/multiple chunks, and both multi-exp algorithms.
- Candidate: 372/372 Boost tests with 142,792,381 assertions (randomized cases
  account for the different assertion count from baseline).
- Focused candidate proof/block suite: 25/25 passed.
- Arithmetic benchmark compiled with C++11 warnings and passed ASan/UBSan.
- Python tools passed syntax checks and were exercised with real daemon runs.
- No consensus constants, serialization, validity conditions, cryptographic
  verification semantics, or database durability settings were changed.

The legacy Python 2 RPC test runner cannot run directly on this Python-3-only
host. The new Python 3 replay supplies real P2P integration coverage for this
change; it does not replace the entire historical RPC suite.

The next measured startup target is the full parameter-file SHA-256 pass:
7,552.6 ms of 8,987.8 ms before networking in the first controlled baseline.
Any optimization must still read and hash every required byte and compare the
same compiled digests. No integrity check may be skipped to improve this time.
