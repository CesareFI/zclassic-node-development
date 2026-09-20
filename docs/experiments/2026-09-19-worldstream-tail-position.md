<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: startup progress tail positioning

The fresh-sync benchmark previously positioned its startup log stream at EOF,
queried that position, then sought back to the tail. Obtain the extent with
`fstat` on the already-open stream and seek directly to the tail. This removes
two stdio positioning calls per observation while preserving the bounded read,
complete-line output, oversized-line refusal and incomplete-read rejection.
The input is the benchmark child's regular log file.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with substantial pre-existing work.
The pre-slice `tools/bench_fresh_sync.c` SHA-256 was
`ee8d86c475f4e9d244f8d2cd642088fdf77956db6556139e3502ca930be099a9`.
This slice changes only the extent lookup, registers its regression in the
existing benchmark target, and adds the regression and this record.

Linux x86_64, GCC 14.2.0, warm synthetic 8,193-byte file, 10,000 observations
per trial, three trials:

| Observation | Before | After |
|---|---:|---:|
| Stdio positioning calls per trial | 30,000 | 10,000 |
| Median wall time | 61.712 ms | 58.471 ms |

Timing is informational and is not an acceptance threshold. The regression
counts actual calls through the extracted production reader and checks its
outputs. These are observer-cost measurements, not end-to-end IBD or time-to-tip
improvements. Kernel syscall tracing was unavailable because ptrace is denied;
the positioning-call counts must not be described as measured syscall counts.

Reproduce without a node, peer, credentials or production datadir:

```bash
bash tools/scripts/bench_fresh_sync_tail_position_selftest.sh --analyze
make bench-fresh-sync-selftest
```

An optional source path selects the baseline; `--baseline` measures without
enforcing the positioning budget. The pre-slice source fails the normal budget
check. Tests cover empty, terminated, unterminated, multiple and blank lines,
exact-fit and oversized output, and a tail beyond filesystem block boundaries.
The existing progress regression separately checks concurrent truncation and
missing logs; the existing I/O regression preserves the kernel read-byte bound.

Validation passed: full `make bench-fresh-sync-selftest`, `make bench_fresh_sync`,
focused C23 `-Wall -Wextra -Werror -pedantic` compilation and GCC `-fanalyzer`,
Bash syntax, pipefail-status, discarded-status, shell-host-assumptions and the
direct architecture-tree gate. Both staged and unstaged `git diff --check`
passed. Aggregate `make lint-fast` exceeded a 60-second preparation bound;
aggregate lint completion is not claimed. The `make check-architecture-tree`
wrapper was also stopped during preparation; its direct gate passed as above.

Consensus and cryptographic validation are unchanged. This slice touches no
node implementation, optional acceleration policy, peer/request scheduling,
database tuning or runtime reliability. No generated outputs, logs, binaries,
credentials or datadirs belong to the slice. Pre-existing edits remain intact.

Publication is blocked: `.git` is read-only and origin's GitHub hostname cannot
resolve. No commit, push or fresh remote-SHA verification is claimed. Baseline
source, raw measurements and an isolated patch are kept outside the tracked
tree under `/tmp/worldstream-tail-position/` for review and later publication.
