<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: avoid idle phase-log seeks

Scope: the cold-start benchmark observer only. No node, consensus, validation,
peer scheduling, database, or acceleration-policy change.

The phase observer reopens its log at every poll and sought its previous
cursor even when the file had not grown. On this host, seeking to an unaligned
EOF also caused stdio to read the final partial buffer again. This is avoidable
observer work while waiting for IBD milestones.

After checking file identity and truncation, return immediately when the
cursor already equals the observed extent. Keep the partial marker tail for
later appends. Identity checks must precede the shortcut so an equal-length
replacement is still scanned.
The phase-completion boolean is accumulated directly, keeping the reader
within the existing complexity limit without changing completion semantics.

## Reproduction and results

Measured on Linux x86_64, GCC 14.2.0, `-std=c23 -O2`, using a warm isolated
32-byte log, missing milestones, and 10,000 reopen/poll/close operations per
sample. No node or network is involved. Wall times include assertions and
file open/stat/close work; they are observations, not test thresholds.

The starting checkout was dirty at commit
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Exact benchmark-source SHA-256:

- Before: `efe83b713465ef6876b3b8df44c9cdee19a0ad188b642d625ab5394c50936817`
- After: `3393cce46439f66a996df46524b3eb00dd49f5acfa1a966558ccece1479f408e`

| Measurement, per 10,000 polls | Before | After |
|---|---:|---:|
| Explicit seeks | 10,000 | 0 |
| Linux read syscalls | 10,001 | 1 |
| Sample 1, seconds | 0.065424 | 0.052626 |
| Sample 2, seconds | 0.057901 | 0.045264 |
| Sample 3, seconds | 0.057618 | 0.045111 |

The one remaining read syscall is `/proc/self/io` measurement overhead.
Median fixture time decreased about 22%. This is an observer microbenchmark,
not evidence of reduced end-to-end IBD or time to sovereign validation.

Run the same-source regression and measurement:

```bash
bash tools/scripts/bench_fresh_sync_idle_log_selftest.sh --analyze
make bench-fresh-sync-selftest bench-fresh-sync-height-selftest bench_fresh_sync
```

Pass `--baseline /path/to/before.c` to measure the old source without enforcing
the zero-seek budget. Running without that flag against the old source failed
at `seeks == 0`, after all 10,000 unnecessary seeks. The new source passes.
The regression covers retained partial markers, append after idle polling,
truncation to empty, stale suffix removal, equal-size file replacement, and
preservation of already observed phases. It compiles the actual observer and
opener extracted from the source; it does not duplicate their implementation.

Focused C23 compilation with warnings as errors and GCC `-fanalyzer` passed.
The aggregate benchmark regressions, height regressions, benchmark build,
shell syntax check, and `git diff --check` passed. The full benchmark build
still reports existing format-truncation warnings in certificate-copy command
construction, outside this slice.

`make lint-fast` did not progress beyond prerequisite setup and was interrupted.
Running its unchanged gate list directly through `tools/lint/run_lint.sh`
reported four failing gates: stray root files, complexity in existing dirty
benchmark functions, stale flag first-use locations, and a Windows guard
selftest unable to create its scratch directory outside the writable roots.
The initial run also caught a new complexity violation in `phase_log_poll`;
direct boolean accumulation fixed that, and a rerun confirms only the unchanged
`wait_for_cookie` and `main` complexity violations remain. No limit or baseline
was weakened. The complete lint gate set is not green.

Publication is unavailable in this environment: `.git` is read-only (fetch
cannot write `FETCH_HEAD`), and the read-only remote check cannot resolve
`github.com`. No commit, push, upstream integration, or remote-SHA verification
is claimed. Existing staged and unstaged work is preserved.
