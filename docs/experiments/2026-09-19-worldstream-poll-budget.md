<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stop benchmark polling at its deadline

Scope: the standalone fresh-sync benchmark's observation loop, not node
runtime, peer scheduling, database behavior, or consensus. Optional Z23
acceleration and independent validation are unchanged.

The starting branch is `agent/worldstream-ibd-20260918` at
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with substantial pre-existing
uncommitted work. The immediate baseline is the saved working-tree
`tools/bench_fresh_sync.c`, SHA-256
`dce6372d4064ed065a150bda77d69f0bb35a0c6e10831d0284a5a64b5b2bd7ef`.
It is not the file at HEAD. The resulting file's SHA-256 is
`393eea7d6b69944979720adc60af2f27566f22dedaf28911d9ea9cd945ed466a`.

## Reproduction and change

Every incomplete observation slept two seconds even when less time remained
in the budget. The loop also admitted a new observation exactly at the
deadline. A deterministic C fixture compiles the actual loop entry and sleep
against a simulated monotonic clock, without launching a node or using the
network. Linux x86_64, GCC 14.2.0, C23, `-O2 -Wall -Wextra -Werror
-pedantic`. There is no cache or storage workload in this measurement.

With a 30-second fixture budget:

| First observation time | Baseline finish | New finish |
|---|---:|---:|
| 27 seconds | 31 seconds | 30 seconds |
| 28 seconds | 32 seconds | 30 seconds |
| 29 seconds | 31 seconds | 30 seconds |
| 29.875 seconds | 31.875 seconds | 30 seconds |
| 30 seconds | 32 seconds, one extra poll | 30 seconds, no poll |
| 30.25 seconds | 30.25 seconds, no poll | Same |

All six cases also run with repeated sleep interruptions. The new regression
fails against the saved baseline. `--baseline` characterizes the old overrun
without claiming it meets the new contract.

The change caps only the last sleep to the remaining budget and refuses to
begin a poll at or after the deadline. Normal two-second cadence and resuming
the unslept interval after EINTR are preserved. The existing outcome test now
requires ten polls finishing at 30 seconds instead of eleven finishing at 32;
its success/failure expectations and grace requirements remain unchanged.

These are simulated observer-delay measurements, not a measured improvement
in actual chain IBD. HTTP observations already in progress, process scheduling,
and final diagnostics can still extend real benchmark runtime beyond the
budget; this slice removes only the unnecessary polling delay.

## Validation and publication

Reproduce with:

```sh
bash tools/scripts/bench_fresh_sync_poll_budget_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_cadence_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_timing_selftest.sh --analyze
make bench-fresh-sync-selftest
make build/bin/bench_fresh_sync
```

The full benchmark suite and normal benchmark build pass. The new deadline
fixture, cadence fixture, and all 24 outcome cases pass strict compilation and
GCC static analysis. Architecture checking via
`bash tools/lint/check_architecture_tree.sh`, shell syntax, and
`git diff --check` pass. Full-file strict compilation/static analysis remain
blocked by pre-existing copy-command truncation warnings; strict optimized
compilation also reports ignored `system` results. The same compiler errors
reproduce on the saved baseline. No warning suppression was introduced.
`make lint-fast` and `make lint check-windows-acceptance` did not complete
within bounded 60-second and 30-second attempts; their last output was
prerequisite template generation. The Make architecture invocation was
interrupted during prerequisites, then its actual architecture script passed
directly. These are incomplete gates, not passes.

Publication is incomplete: Git metadata is read-only (`FETCH_HEAD` and
`index.lock` writes fail), and `git ls-remote origin` cannot resolve GitHub.
No commit, push, remote-SHA verification, or full publication-gate success is
claimed. Existing dirty work is preserved. Only benchmark source, fixtures,
test registration, and this note belong to the slice; temporary logs, binaries,
baseline copies, and patch output remain outside the repository in `/tmp`.
