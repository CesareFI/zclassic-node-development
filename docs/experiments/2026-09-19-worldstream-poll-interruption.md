<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: preserve IBD trials across interrupted child observations

Owned surface: the steady-state child observation in `tools/bench_fresh_sync.c`,
its isolated regression, and registration in `bench-fresh-sync-selftest`.
The existing outcome and timing fixtures gain only the errno header needed to
compile that production block. No node runtime, peer scheduling, database,
consensus, validation, acceleration flags or production datadir changes.

## Baseline and witness

Branch: `agent/worldstream-ibd-20260918`.
HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`.
The checkout contains extensive earlier staged, unstaged and untracked work.
This slice is incremental to that working source, not to HEAD alone.
Entry benchmark source SHA-256:
`7f54895e99a7dad9b94e7affa1cac1147f867f3688d99b966c4a0565b9829104`.
Updated benchmark source SHA-256:
`8453e58b0ba63f0d3f95756ac950f8f85d100a9a8b44faed2462f4b49d37cf92`.

The startup observer already retried `waitpid` on EINTR. The steady-state
observer instead declared node death on every nonzero return, abandoning the
trial and printing an undefined status on errors. It now retries only EINTR,
immediately, and prints errno context for other errors. Child exit still fails.

The regression compiles the actual child-observation block and injects zero
through three interruptions before each of three outcomes: live, exited, and
ECHILD. Before the change, only 1/4 live trials survive; afterward 4/4 survive.
Afterward each case makes exactly interruptions + 1 wait calls, with no added
polling sleep or diagnostic subprocess on the live path. Exited and missing
children fail in all eight cases. Stale EINTR after a successful wait does not
trigger another retry. The new invariant fails against the saved entry source.

This is deterministic benchmark-reliability evidence, not a measured live
time-to-tip improvement or a claim about real-world interruption frequency.
No network, credentials or live node is used by the regression.

## Validation

```sh
bash tools/scripts/bench_fresh_sync_poll_interrupt_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_startup_interrupt_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_height_selftest.sh --analyze
```

All pass with C23, `-Wall -Wextra -Werror` and GCC 14.2 static analysis.
The new test also uses `-pedantic`. It accepts `--baseline` and an optional
source path to reproduce the earlier live-trial loss. The outcome fixture
retains all 24 deadline, grace, missing-observation and recovery assertions.

Executing the aggregate target's shell recipes directly passes 16/17 scripts.
The timing fixture expects completion at 21 seconds but observes 19; the same
failure reproduces against the saved entry source. Its assertions are unchanged.
The standalone benchmark links with the Makefile's compiler recipe. Existing
ignored-system-result and certificate-copy truncation warnings reproduce on
the entry source. Bash syntax and `git diff --check` pass.

The aggregate Make target and `make lint-fast` each exceed a 45-second bounded
attempt without a verdict; `make check-architecture-tree` likewise exceeds
30 seconds. They report missing Tor archives and unchanged template generation.
The standalone pipefail-status gate and its selftest pass. No prerequisite or
acceptance threshold was bypassed to claim the Make targets green.

## Publication boundary

Git metadata is read-only: fetching fails opening `.git/FETCH_HEAD`; GitHub
DNS resolution also fails for `git ls-remote origin`. No commit, push, upstream
integration or fresh remote-SHA verification is claimed. Preserve the earlier
dirty work and publish only a coherent validated slice to the designated
development branch when the environment permits normal Git operations.
Temporary fixtures and binaries reside outside the source tree and are not
part of the change. Consensus and independent validation remain unchanged.
