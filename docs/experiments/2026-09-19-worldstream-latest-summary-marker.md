<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stop enumerating older snapshot summaries

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The benchmark's reverse snapshot-summary reader searched every occurrence of
`UTXOs in` within a chunk to find its last occurrence. Repeated summaries made
this display-only observation perform thousands of unnecessary substring
searches. It now checks the last `U` first. An exact marker there is necessarily
the latest match; a nonmatching candidate retains the original full search.
Chunks without a `U` need no substring search.

The 16 MiB read limit, chunk overlap, exact latest offset, binary-input refusal,
line-length refusal and observation semantics remain unchanged. No node source,
consensus predicate, cryptographic validation, optional acceleration policy,
peer scheduling, database code or production state changed.

## Baseline and measurement

The baseline is the working benchmark at entry, including earlier uncommitted
work, SHA-256:
`84f71a6f54b5d031f9ec1cb6266bb18e17f7da341e5d134b85f272bd190b821c`.
It is not pristine HEAD. This slice adds only the final-candidate lookup, one
self-test recipe, its regression script and this record. Earlier staged,
unstaged and untracked work is preserved.

Linux x86_64, GCC 14.2.0, glibc 2.39, `-O2`; synthetic 16 KiB text files,
warm ordinary filesystem caches, no node, RPC, peer or canonical datadir.
The regression counts substring calls while measuring 2,000 lookups per trial.
Three sequential repetitions, baseline before candidate; host load uncontrolled.
Times below are medians in milliseconds, not acceptance thresholds.

| Fixture | Baseline | Candidate |
|---|---:|---:|
| No marker | 6.271 | 6.151 |
| One recent marker | 5.060 | 4.737 |
| One early marker | 4.536 | 4.413 |
| 1,024 markers, latest candidate matches | 45.177 | 4.560 |
| Same markers with a later unrelated `U` | 45.082 | 45.253 |

The repeated-marker fixture drops from 2,050,000 substring calls to zero and
about 90% less measured wall time. The fallback retains the old work. These
are observer microbenchmarks: frequency in real logs and end-to-end IBD or
time-to-tip improvements are not established.

Reproduce:

```sh
bash tools/scripts/bench_fresh_sync_latest_marker_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_latest_marker_selftest.sh --baseline /path/to/before.c
```

## Validation and remaining gates

The new test passes exact latest-offset, incomplete-marker and unrelated-suffix
cases. The entry baseline fails its search-work budget. A mutation returning
the chunk start instead of the latest offset fails the value assertions.
The changed reader compiles as C23 with `-Wall -Wextra -Werror -pedantic` and
passes GCC `-fanalyzer`.

All 35 scripts in the existing `bench-fresh-sync-selftest` recipe passed when
run directly, each with a 60-second limit. This includes summary budget,
overlap, read-I/O, binary logs, marker boundaries, startup, deadlines, command
refusals, timing, outcomes and report demand. The aggregate Make initialization
was not required for these direct fixture tests. The complete benchmark links
with the flags used by its Makefile recipe, plus C23.

Adding strict warnings to the complete benchmark exposes seven existing
diagnostics: five ignored `system()` results and two possible command-buffer
truncations. The same diagnostics reproduce on the entry baseline; this slice
does not suppress or change them. No full strict-build pass is claimed.

Shell syntax, architecture-tree, pipefail-status, discarded-status and
shell-host-assumption checks pass. `git diff --check` passes. A comparison of
the entry and final staged diffs confirms the index is unchanged; all unrelated
tracked diffs also compare byte-for-byte equal.

`timeout 180 make lint-fast` expired during initialization after reporting
unchanged generated templates; no aggregate lint pass is claimed. The public
node binary is absent, so live IBD and chain acceptance were not run. The lint
gap prevents declaring this slice ready for publication.

Temporary baseline snapshots, measurement output and the isolated slice patch
live under `/tmp/worldstream-summary-last-marker/`; they are not source
deliverables. Only source, test, Makefile wiring and this record belong in a
commit. Never stage the complete dirty benchmark or Makefile as this slice.

Publication is incomplete. Fetch cannot write `.git/FETCH_HEAD`, and staging
cannot create `.git/index.lock`: the sandbox mounts Git metadata read-only.
The origin branch lookup also fails because GitHub cannot resolve. No commit,
push, upstream integration or exact remote-SHA verification is claimed. The
checkout remains on the required development branch.
