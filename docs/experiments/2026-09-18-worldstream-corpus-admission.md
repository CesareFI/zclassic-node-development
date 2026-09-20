<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: refuse substitution of an explicitly requested benchmark corpus

Scope: corpus admission in `tools/serial_bench.c`, the standalone block-body
deserialization benchmark used to investigate IBD cost. This is measurement
qualification, not a measured reduction in end-to-end IBD time.

## Baseline and reproduction

Branch: `agent/worldstream-ibd-20260918`.
HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`.
The checkout already contained extensive staged and unstaged work. The entry
version of `tools/serial_bench.c` had Git blob identity
`431e9bc98ee6d7292ba2605f3720d8fd73b0a148`, including the earlier complete-parse
checks. That work was preserved. This slice changes only corpus selection in
`main`, adds `serial_bench_corpus_selftest.sh`, and invokes it from the existing
observation selftest.

Host: Linux 6.8.0-139-generic, x86_64, AMD EPYC 7402P, GCC 14.2.0.
Build: `make serial_bench`, with the standalone source set and
`-std=c23 -O3 -march=x86-64-v3 -Wall -Wextra -Werror -pedantic`.
No live node, production datadir, peer, or network benchmark was used.

On the entry version, requesting a nonexistent corpus with
`--corpus=/tmp/nonexistent-corpus.hex --reps=31 --csv` returned success and
three verified measurement rows. The observed shipped-mode median was
1,954 ns/block. These numbers measured a substituted synthetic block, not the
requested chain data. CSV omitted the synthetic-data banner. This value is a
witness to misleading output, not a performance baseline for chain replay;
host load and cache state were uncontrolled.

The new selftest failed against the entry binary: the missing-file case
returned 0 instead of 1. Thus parity over the replacement workload could appear
to qualify an IBD benchmark whose requested input had never been loaded.

## Change and validation

An explicit `--corpus` now selects only the file loader. If it fails, the
benchmark names the requested corpus, exits 1, and emits no measurements.
Omitting `--corpus` retains the existing synthetic control. Nothing in the
timed parse loop, serialization code, or node validation changes.

`make bench-serial-selftest` passed. The new regression covers missing, empty,
non-hex-only, blank-only, directory, and empty-path inputs in text and CSV
modes (12 refusals), plus valid-file and omitted-corpus controls. The earlier
four incomplete-parse refusals and parity control also passed.

Additional validation passed:

- GCC `-fanalyzer` compilation with warnings treated as errors.
- The complete observation/corpus suite under ASan and UBSan. Leak detection
  was disabled because of the process-tracing environment; leak freedom is
  not established by this run.
- Shell syntax, discarded-status, pipefail, raw-allocation, architecture-tree,
  and consensus-core seal checks; `git diff --check` and exact incremental
  diff review.

`make lint-fast` ran but failed on pre-existing stray `.agents`/`.codex` root
entries, `bench_fresh_sync.c:main` complexity, 18 unrelated flag first-use
pointers, and a Windows-guard selftest unable to create its scratch directory
outside the writable workspace. None of these gates was weakened. The Make
invocations also reported unavailable zlib downloads; the standalone benchmark
build and focused tests nevertheless completed successfully.

## Limits and publication

The loader can still skip malformed lines in an otherwise loadable corpus or
stop at its block limit; partial-corpus admission and CPU-affinity qualification
remain separate work. This slice only prevents failed explicit loading from
substituting a different workload. There is no time-to-tip speedup claim.
Consensus source and semantics, mandatory independent validation, optional
acceleration policy, wallet state, and Hetzner-owned runtime work are unchanged.

No logs, binaries, caches, benchmark output, or credentials are part of this
source slice. Publication is blocked: Git metadata is read-only in this
session (`git fetch` cannot write `.git/FETCH_HEAD`), and the direct origin
branch lookup fails because GitHub DNS cannot resolve. Origin also has no
`main` ref. No commit or push was made, and the remote SHA was not verified.
