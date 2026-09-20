<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound startup polling under interrupted sleeps

The fresh-sync benchmark sleeps between RPC-cookie and child-status checks.
An interrupted `usleep` previously triggered another observation immediately,
so signals increased observer work during startup. Retain the half-second
observation cadence by retrying only the time remaining until the original
wake time. Keep the overall 300-second monotonic deadline. A non-interruption
sleep failure now reports context and refuses setup instead of busy-polling.
The benchmark retains ownership of its child for normal cleanup.

Baseline branch: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with extensive pre-existing edits.
Pre-slice `tools/bench_fresh_sync.c` SHA-256:
`82ca8f40509fa84d2d30f630c332b928cabb74c49424d5972bc177207be4f8c7`.
Only the sleep retry block, one Makefile test registration, the new regression
and this record belong to this slice.

The deterministic C fixture executes the actual startup function with a fake
monotonic clock, cookie reader, sleep and child observer. Interrupted sleeps
advance by at most 5 ms, modelling 200 interruptions/second. No node, real
signal delivery, network, production datadir or credentials are used. Built
on Linux x86_64 with GCC 14.2.0 and C23 `-O2 -Wall -Wextra -Werror -pedantic`.

| Scenario | Before child polls | After child polls | Before cookie checks | After cookie checks |
|---|---:|---:|---:|---:|
| Cookie ready at 10 s, uninterrupted | 20 | 20 | 22 | 22 |
| Cookie ready at 10 s, interrupted | 2,000 | 20 | 2,002 | 22 |
| Cookie absent at 300 s, interrupted | 60,001 | 600 | 60,003 | 602 |

Both versions observe the cookie at exactly 10 simulated seconds and the
timeout at exactly 300. Sleep retries themselves remain proportional to signal
delivery (2,014 after versus 2,000 before in the ten-second case); this removes
extra filesystem and child-status observations, not signal handling work.
These are observer call counts, not measured wall-clock or end-to-end IBD
speedups. Real Worldstream time-to-tip still requires an authorized host run.

Reproduce:

```bash
bash tools/scripts/bench_fresh_sync_startup_sleep_selftest.sh --analyze
make bench-fresh-sync-selftest
```

The focused script also accepts a source path and `--baseline`. The unchanged
pre-slice source fails the poll-count assertion; baseline mode measures it
without that gate. Positive fixtures cover uninterrupted startup, repeated
interruptions, deadline expiry, progress cadence, exact cookie bytes and
immediate refusal on a non-EINTR sleep error. Existing startup-budget and
waitpid-interruption fixtures also pass with GCC `-fanalyzer`.

The full fresh-sync benchmark selftest target passes, as do Bash syntax,
pipefail-status, discarded-status, shell-host-assumptions, architecture-tree
checks and staged/unstaged `git diff --check`. The complete benchmark builds
with its normal flags; the pre-existing discarded `system()` result and
format-truncation warnings reproduce on the saved baseline. Aggregate
`make lint-fast` exceeded a 55-second bound during preparation; it is not
claimed as passing.

Consensus, validation, optional acceleration, node behavior and Hetzner-owned
scheduling/database/runtime code are unchanged. No secrets, generated files,
logs, binaries, caches or production state are part of this slice.

Publication is blocked: `.git` is read-only, preventing fetch and commit;
the origin lookup also fails because `github.com` cannot resolve. Local HEAD
and the cached development-branch tracking ref match, but that is not remote
verification. No commit or push is claimed. The isolated slice patch and
fixture output are kept under `/tmp/worldstream-startup-sleep/` for review.
