<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream startup progress observation

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Substantial earlier staged and
unstaged work was preserved. The baseline is the working-tree source saved
before this slice, not that commit's clean source. Linux x86_64, GCC 14.2.0,
Bash 5.2.21; local temporary fixtures, no node or network traffic.

The fresh-sync benchmark used a shell and `tail -1` for every ten-second
startup progress report while waiting for the RPC cookie. It now reads a
bounded suffix directly. Each observation requests at most 256 bytes,
independent of startup log size. The complete last line must fit, including
any terminating newline; oversized or incomplete reads still yield no progress
text. The caller's cookie polling, timeout, child checks and progress schedule
are unchanged. Failure-only multi-line diagnostics keep their existing path.

Three warm-cache runs, each making 500 observations of the same sparse 64 MiB
log ending in `progress\n`:

| Run | Before | After |
|---|---:|---:|
| 1 | 1.354204 s | 0.004328 s |
| 2 | 1.350902 s | 0.004324 s |
| 3 | 1.353714 s | 0.004309 s |
| Median | 1.353714 s | 0.004324 s |

The fixture median falls about 99.7%, from 2.707 ms to 0.00865 ms per read.
This removes observer subprocess overhead, not a measured chain-validation
bottleneck. At the current reporting interval, a full 300-second startup wait
has 29 progress reads; the measured per-read delta suggests roughly 78 ms
saved in that case. That is an extrapolation, not live startup or time-to-tip
evidence. No IBD acceleration claim follows from this microbenchmark.

The regression compiles the actual production helper and progress call site.
It covers empty files, terminated/unterminated and empty final lines, CRLF,
embedded NULs, exact-fit and oversized lines, long history, file truncation,
missing files, and a simulated short read. It counts requested read bytes and
subprocess calls; timings are descriptive, not pass thresholds. The saved
baseline passes behavior checks and fails the zero-subprocess assertion with
1,520 command launches, including the 1,500 timed reads. The new path uses zero.

Reproduce with a saved pre-change source:

```bash
bash tools/scripts/bench_fresh_sync_progress_selftest.sh --bench /tmp/before.c
bash tools/scripts/bench_fresh_sync_progress_selftest.sh --bench --analyze
```

Source SHA-256 before:
`d4dd0d5bc709f9115932493740374609043d82848fd33ea4ccfc4976dceb7e20`;
after: `bd90cb3bbdd52a115b7714b03a770d38f614b697b86a1e17bf9d192b6471c48d`.

Validation:

- New regression and all 13 existing startup cases pass, including C23
  `-Wall -Wextra -Werror` and GCC `-fanalyzer`. The adapted startup fixture
  also passes against the saved baseline with its assertions unchanged.
- Existing phase-log, complete-log, command-reader, HTTP-deadline, page-size,
  explorer-readiness, outcome/grace and height-demand regressions pass directly.
- The existing timing regression fails identically before and after:
  `t_done` is 19 seconds while the assertion expects 21. Its assertion and the
  timing loop are unchanged. The overall benchmark suite is not green.
- The full benchmark executable builds with the existing target's flags.
  Its seven existing warnings (unchecked `system` calls and copy-command
  truncation) match the saved baseline. No warning was suppressed.
- `make bench-fresh-sync-selftest` and `make lint-fast` each time out after
  60 seconds during setup, before suite/lint results. No aggregate pass is
  claimed. The new regression is registered in the benchmark Make target.
- Direct pipefail-status, discarded-status, shell-host-assumption and
  architecture-tree gates pass. Tracked-tree gates do not cover the new
  untracked script; its Bash syntax and compiled regression pass separately.
  ShellCheck and Clang are unavailable. `git diff --check` passes.

Only benchmark observation, its tests, Make test wiring and this note belong
to the slice. Consensus source has no diff. Validation, optional acceleration,
peer/request scheduling, database behavior and node runtime are unchanged.
The incremental diff against the saved working tree was inspected; no secrets,
generated artifacts, logs, caches, binaries or temporary output are included.

Publication is incomplete: `.git` is read-only, so fetch cannot write
`FETCH_HEAD`; `origin/main` is absent locally, and an independent
`git ls-remote origin` fails to resolve the origin host. No commit or push was
made, and no remote SHA was verified. Branch and HEAD remain as recorded
above. Publication requires writable Git metadata, working origin access,
separation from earlier dirty work, and resolution of the broader test/lint
limitations without weakening assertions.
