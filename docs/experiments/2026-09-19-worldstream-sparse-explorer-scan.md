<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream sparse explorer marker scan

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Baseline is the working-tree
benchmark at session entry, including earlier uncommitted Worldstream work.
Linux x86_64, GCC 14.2.0, C23 `-O2`, local temporary files with warm page
cache and uncontrolled ambient load. No node, datadir or network was used.

The explorer readiness observer skipped the prefix before the first possible
marker start, then compared every byte in the remaining chunk. One false
start per 8192 bytes therefore caused 8,364,032 comparisons for a 16 MiB
response. The observer now alternates bounded candidate searches with short
64-position scans. Sparse gaps are skipped; dense candidates amortize the
search across a window. The same fixture takes 131,072 comparisons, about
98.4% fewer. Memory remains bounded by the existing chunk and overlap buffer.
Response draining, read-error and curl-status checks, binary byte matching,
HTTP deadline and read-boundary overlap remain intact.

Each timing sample is five observations of one 16 MiB file; the table gives
the median of three samples, in seconds. Timing builds disable comparison
counting. These are observer overhead measurements, not evidence of an
end-to-end IBD or sovereign-validation speedup.

| Response body | Before | After |
|---|---:|---:|
| No candidate starts | 0.025427 | 0.025397 |
| Dense candidate starts (`L`) | 0.066514 | 0.063258 |
| One false start per 8192 bytes | 0.046013 | 0.025758 |
| Real marker at the end | 0.025251 | 0.025409 |

The sparse fixture takes about 44% less wall time. Timing is descriptive;
the regression gates comparison work independently of host load. It fails
the baseline at a 524,288-comparison budget and passes the changed observer.
It also checks marker positions within and beyond each scan window, read
overlap, dense candidates, NUL gaps, end-of-body matches and full draining.
Existing tests retain their read-error and failed-transfer assertions.

Reproduce with a saved pre-change benchmark source:

```bash
bash tools/scripts/bench_fresh_sync_sparse_marker_selftest.sh /tmp/before.c
bash tools/scripts/bench_fresh_sync_sparse_marker_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh --measure /tmp/before.c
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh --measure
```

The first command is expected to fail. Source SHA-256:

- Before: `9f5f22fe5fea7affdc2b707e88e07df8af7b1f9eb1d297045b3cdd2f8ad98b4b`.
- After: `3f94cab60bbb4303f37ae406a6297a68e1905f650871a07634e6ca7a792614e2`.

Validation:

- New regression and existing scan, readiness and outcome fixtures pass with
  GCC `-fanalyzer`; extracted observers compile with C23 warnings-as-errors.
- The new regression passes AddressSanitizer and UndefinedBehaviorSanitizer.
  LeakSanitizer cannot run under this environment's tracing; that dimension
  is unobserved. The address/undefined run disables leak detection explicitly.
- All 14 `bench_fresh_sync_*selftest.sh` scripts were executed directly:
  thirteen pass. The pre-existing timing test expects completion at 21 s
  but observes 19 s. Baseline and changed failure logs are byte-identical;
  neither the test nor its assertions changed.
- Complete baseline and changed benchmark executables build. Their compiler
  diagnostics match after normalizing source paths and line numbers.
- `make bench-fresh-sync-selftest` and `make lint-fast` each time out after
  45 seconds during initialization, before aggregate results. No full lint
  or aggregate test pass is claimed.
- Direct architecture-tree, pipefail-status, discarded-status and shell-host
  checks pass. Those tracked-tree checks do not include the new untracked
  script; its syntax and compiled checks ran separately. `git diff --check`
  passes.

Owned changes are the observer scan in `tools/bench_fresh_sync.c`, one Make
test invocation, the new sparse-marker regression and this note. Incremental
diffs against session-entry copies were reviewed; unrelated pending work is
preserved. Consensus sources and semantics, independent validation, optional
acceleration policy and Hetzner-owned runtime, scheduling and database work
are unchanged. This slice includes no secrets, generated output or binaries.

Publication remains incomplete: `.git` is read-only, fetch cannot write
`FETCH_HEAD`, and the local `origin/main` ref is absent. An independent
`git ls-remote origin` query fails GitHub DNS resolution. No commit, push or
remote SHA verification is claimed. Publication requires writable metadata,
origin access, separation from earlier pending changes and completion of
outstanding integration gates without weakening assertions.
