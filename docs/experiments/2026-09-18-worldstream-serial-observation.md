<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: refuse incomplete block-deserialization measurements

Scope: standalone IBD performance instrumentation in `tools/serial_bench.c`.
No node, consensus, scheduling, database, wallet, or acceleration policy changes.
This slice claims measurement correctness, not an improvement in time to tip.

## Baseline and witness

Checkout HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The benchmark file was clean at entry;
its baseline Git blob was `bcbaadf7c73b223cf3ab27d7dd6cf76a2f190c55`.
Other existing staged and unstaged work was preserved.

Host: Linux 6.8.0-139-generic, x86_64, AMD EPYC 7402P, GCC 14.2.0.
Build: the standalone `serial_bench` source set and Makefile flags
(`-std=c23 -O3 -march=x86-64-v3 -Wall -Wextra -Werror -pedantic`).
Fixtures were local synthetic bytes in `/tmp`; no network, chain datadir,
or live peer was involved. Corpus data was loaded into memory before timing;
the benchmark discarded its normal warmups and pinned itself to CPU 0.
Ambient host load was uncontrolled.

Reproduce against the baseline binary:

```sh
printf '00\n' > /tmp/serial-short.hex
build/bin/serial_bench --corpus=/tmp/serial-short.hex --reps=31
```

The one-byte corpus returned success, reported three matching parity digests
over one block and **zero transactions**, then reported **20,000,000 blocks/s**
(50 ns/block for the shipped allocation mode). The observer hashed a common
failure marker, while the timer silently skipped failed parses but divided by
the entire corpus count. Thus failed work could look like fast block decoding
and contaminate the search for an IBD bottleneck.

## Change and focused acceptance

Both observation and timing now use one checked parse. Every loaded entry
must deserialize successfully and consume its entire byte stream. Failure
names its one-based corpus entry and consumed byte count, exits 2, and emits
no throughput rows. Ownership fields are initialized for partial-parse cleanup
without introducing header-buffer zero filling into the timed workload.
The existing parser and its acceptance semantics are unchanged; refusing
trailing bytes here enforces the benchmark's one-block-per-entry framing.

```sh
make bench-serial-selftest
```

The regression fails against the baseline (exit 0 instead of 2). It passes
against the candidate for truncated header, partial transaction, trailing-byte,
and mixed complete/rejected corpora. Complete serialization and the built-in
synthetic/parity self-test remain successful controls. The serialization fixture
does not claim consensus validity.

A separate 501-repetition synthetic control measured shipped-mode median/p90
of 2064/2074 ns before and 2114/2134 ns after. This single warm comparison
shows the cost of the added checks in that workload, not a chain throughput
estimate or a statistically qualified performance regression threshold.

Validation completed: focused Make target, warning-clean build, GCC
`-fanalyzer` compilation, shell syntax, discarded-status and pipefail checks,
raw-allocation lint, architecture-tree and consensus-core seal checks, and
`git diff --check`. The same regression passed an
AddressSanitizer/UndefinedBehaviorSanitizer build. LeakSanitizer could not run
under the environment's process tracing; that rerun used
`ASAN_OPTIONS=detect_leaks=0` and does not establish leak freedom.
Full `make lint` did not complete within a bounded 120-second attempt: its
prerequisites encountered unavailable Tor/submodule and zlib downloads, then
were still compiling unrelated node objects when the timeout terminated them.
Full lint is **unverified**, not passed. The standalone benchmark build and
focused regression completed despite those unavailable vendor prerequisites.

## Limits and publication

This is a narrow loaded-block observation fix. Corpus-loader behavior (including
skipped non-hex lines and the synthetic fallback), hash/serialization allocation
failure reporting, and CPU-affinity admission are separate remaining benchmark
qualification gaps. No full-history validation or real IBD speed claim is made.

The only Makefile addition in this slice is `bench-serial-selftest`; the other
pre-existing Makefile changes are not part of it. No logs, binaries, benchmark
output, or private operational material belong in the slice.

Publication remains blocked: fetch cannot write `.git/FETCH_HEAD` (read-only
filesystem), `origin/main` is not available locally, and the remote lookup
cannot reach GitHub DNS. Staging source files is permitted, but that does not
resolve the missing integration and full-lint evidence. Do not
interpret the existing remote-tracking ref as a freshly verified remote SHA.
