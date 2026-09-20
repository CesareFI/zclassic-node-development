<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: preserve startup measurements on interrupted waits

Branch: `agent/worldstream-ibd-20260918`, entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.
Scope is the fresh-sync benchmark's startup observer, not node runtime.

The startup observer treated every nonzero `waitpid` result as child death.
An EINTR result therefore discarded the measurement even though no child exit
was observed. Retry that observation immediately, using the same EINTR handling
already present in benchmark cleanup. Do not change polling cadence, startup
budget, cookie admission, or the refusal on a child exit or permanent wait error.

The reproducer compiles the actual startup function with a simulated clock,
child wait, and inert cookie. At 10 seconds, inject zero through three EINTR
results, then report either a live child, an exited child, or ECHILD. The live
child publishes its cookie at 10.5 seconds. No node, network, or real datadir is
used. This tests interrupted-call handling; it does not establish that this
host's nonblocking wait produces EINTR in practice, nor an end-to-end IBD speedup.

| Live-child fixture | Entry baseline | Candidate |
|---|---|---|
| No interruption | Ready at 10.5 simulated seconds | Same |
| One interruption at 10 seconds | False failure at 10 seconds | Ready at 10.5 seconds |
| Up to three interruptions | First interruption aborts | No extra polling sleeps |

All 12 candidate cases pass, including permanent error and real-exit refusals.
The new regression is called by the existing startup self-test so its existing
Make target includes it. Reproduce with:

```sh
bash tools/scripts/bench_fresh_sync_startup_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_cleanup_selftest.sh
bash tools/scripts/bench_fresh_sync_progress_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh
```

These pass on Linux x86_64 with GCC 14.2. The actual extracted startup function
compiles with C23, `-Wall -Wextra -Werror`, and GCC `-fanalyzer`. Bash syntax,
architecture-tree, shell-host-assumption, pipefail-status, discarded-status,
and `git diff --check` checks pass.

Broader validation is incomplete. The existing timing self-test expects total
completion at 21 seconds but observes 19 on both baseline and candidate. Full
translation-unit compilation with `-O2 -Wall -Wextra -Werror` fails identically
on both: five ignored `system` results and two potentially truncated copy
commands. These pre-existing failures and their assertions were left intact.
`timeout 50 make lint-fast` expired during initialization (exit 124); no
aggregate pass is claimed.

Earlier staged, unstaged, and untracked work remains intact. The entry source
SHA-256 is `76d6970e46791330d480e9630713ac8090bb7e32fba7a89e77d587695286b3f5`.
Baseline copies and a slice-only patch are under
`/tmp/worldstream-startup-interrupt/`. Do not stage the entire dirty benchmark
or startup self-test as this slice. No consensus, custody, validation predicate,
optional-acceleration policy, or Hetzner-owned implementation changed. The slice
contains source, a regression, and this note only.

Publication remains blocked: `.git/FETCH_HEAD` is read-only, `origin/main` is
unavailable locally, and GitHub DNS resolution fails. No commit, push, or remote
SHA verification is claimed; the branch remains unchanged.
