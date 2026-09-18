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

A second replay pair reached the same height and hash in 161.97 s before and
141.74 s after (12.5% less elapsed time), using 3,074.70 and 145.27 CPU-seconds,
respectively. It again downloaded exactly 27,783,019 bytes with 5,000 block
requests and no timeouts. Across both pairs, the observed elapsed reduction is
12.5–14.4%; this remains a measurement of the historical prefix, not the whole
chain. The optimization and its tooling are preserved in commit `20847e87a`.

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

## Parameter hashing before peer startup (2026-09-18)

After the OpenMP improvement, startup still spent 7.54 seconds hashing parameter
files with the legacy scalar SHA-256 implementation. The candidate uses the
existing libcrypto dependency's SHA-256 backend for these file-integrity checks
only. Consensus hashing and serialization code are untouched. Every byte is
still read, the same compiled digests are compared, and cache eligibility,
Sprout verification-key checks, refetch policy, and Rust's independent parameter
verification remain unchanged.

The stream helper owns its digest context and fixed 256 KiB heap buffer. It
checks all digest operations, distinguishes read errors from EOF, and clears the
output on failure. `check_file_hash` now closes its file through RAII on every
path. A read error no longer spins in a `while (!feof(file))` loop.

Alternating candidate/control/candidate fresh-datadir runs against the local
replay measured:

| Measurement | Control | Candidate 1 | Candidate 2 |
| --- | ---: | ---: | ---: |
| Full parameter SHA-256 phase | 7,538.5 ms | 1,303.7 ms | 1,304.5 ms |
| Total AppInit2 startup | 8,779.4 ms | 2,545.0 ms | 2,553.9 ms |
| First peer observed by RPC | 9.01 s | 3.00 s | 3.00 s |
| First accepted block observed by RPC | 10.05 s | 3.00 s | 3.00 s |

All three logs report `param-cache: 0 skipped, 5 hashed`. All five digests are
identical between the control and both candidates. Startup decreased by about
71% on this host. Parameters were installed beforehand and warm in the OS cache;
these timings do not include downloading parameters. RPC times have one sample
interval of uncertainty; phase timings come from the node's existing timer.

A further 5,000-block replay completed in 138.25 s, using 140.98 CPU-seconds and
reaching the same previously recorded tip hash, with 5,000 requests and no
timeouts. Compare this with the preceding OpenMP-only runs at 141.74–143.11 s;
the precise total-time gain varies with normal execution noise. The repeatable
startup-phase improvement is the main evidence for this second change.

The standalone file benchmark reads the 910,173,851-byte Sprout proving file:
legacy 4.426 s, candidate 0.762 s, with the same digest. Disabling OpenSSL's x86
CPU capabilities via `OPENSSL_ia32cap=0` measured 2.999 s. Backend acceleration
is platform/build dependent; the repository's portable OpenSSL recipe uses
`no-asm`, so the native host's SHA-accelerated result must not be claimed for
every release build.

```sh
g++ -std=c++11 -O2 -Wall -Wextra -Werror -Isrc \
  qa/zcash/benchmark-parameter-hash.cpp src/sha256.cpp -lcrypto \
  -o /tmp/benchmark-parameter-hash
/tmp/benchmark-parameter-hash legacy /path/to/sprout-proving.key
/tmp/benchmark-parameter-hash candidate /path/to/sprout-proving.key
```

Focused tests cover SHA-256 known vectors, padding boundaries, exact/partial
256 KiB chunks, binary input, initial stream failures, and a read failure after
a complete chunk. The file benchmark also passed ASan/UBSan on the actual
parameter file and compiles as C++11 with `-Wall -Wextra -Werror`.
All 177 GoogleTests passed, including the new tests and the existing proof,
transaction, and validation suites. No additional warnings arose in the helper;
the full legacy build still emits pre-existing warnings in unrelated code.

## Recovering a stalled initial header source (2026-09-18)

During early IBD, a single peer owns header synchronization. A connected peer
that answers pings but supplies no headers could retain that slot indefinitely,
even with another usable outbound peer connected. A loopback regression using
ordinary mainnet data reproduced zero headers and zero blocks after 90 seconds
on the preceding parameter-hash build.

The candidate tracks each header source's highest-work validated header and its
last progress time. After 60 seconds without progress, it disconnects the source
only when another preferred peer has completed its handshake, no block requests
remain outstanding from the source, and synchronization is still more than a
day behind. Empty or duplicate header responses do not reset the deadline.
Existing cleanup releases the header slot. There is no ban, and all header and
block validation remains unchanged. A sole source is retained.

The same regression with the final candidate accepted its first headers at
63.22 seconds and finished all 100 blocks at 64.23 seconds. It made exactly 100
block requests, logged one header-stall disconnect, and reached the expected
tip `00001071e9da677300cf65b92f954b00184f941e6b51e9e6d5927be0ac277271`.
The healthy-only case accepted headers at 3.00 seconds without a disconnect.
These are controlled availability-fault results, not a general steady-state
throughput or total-chain IBD claim. Timing has approximately one second of RPC
sampling uncertainty.

The Python 3 integration driver creates private scratch datadirs and loopback
fixtures, retaining all logs for inspection. Its scenarios cover failover,
healthy operation, retaining a sole source, and retaining the current source
when the alternative has not completed its handshake:

```sh
python3 qa/zcash/test-header-progress.py \
  --daemon /path/to/candidate-zclassicd --blocks /path/to/stopped-capture/blocks \
  --output-dir /tmp/header-progress-failover --scenario failover
# Repeat with a new output directory for healthy, sole, and unready.
```

The fixture is fixed to loopback. Its fault modes are opt-in test controls;
normal replay still serves all requested captured headers and blocks.
All four scenarios passed with the final binary. The full 177-test GoogleTest
suite and the 32 selected Boost networking/validation tests passed (46,068,001
assertions). Python syntax checks and `git diff --check` passed. Compiler
warnings were reviewed and remain in pre-existing legacy code.
