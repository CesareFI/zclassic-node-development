<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream benchmark teardown latency

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.
The baseline is the working-tree benchmark saved before this slice; extensive
earlier staged and unstaged work remains intact. Measurements use Linux
x86_64, GCC 14.2.0, local disposable child processes, and uncontrolled ambient
load. No node, network, wallet or production datadir participates.

The fresh-sync benchmark always slept 500 ms during cleanup, even after
reaping its child. It now checks for exit every 10 ms, returning once the child
is reaped. A monotonic deadline retains at least 500 ms of graceful shutdown
before SIGKILL for an unresponsive child. Interrupted sleeps do not shorten
that deadline. Interrupted waits are retried, and the child handle is cleared
after reaping or a wait error so repeated cleanup cannot reuse it.

The real-process fixture waits until its child has blocked SIGTERM before
starting the measurement. The child receives SIGTERM through `sigwait`, sleeps
20 ms and exits. Three consecutive observations from the final test run:

| Run | Before, seconds | After, seconds |
|---|---:|---:|
| 1 | 0.500096 | 0.030211 |
| 2 | 0.500130 | 0.030322 |
| 3 | 0.500100 | 0.020208 |
| Median | 0.500100 | 0.030211 |

This removes approximately 470 ms of teardown latency for this fixture.
It does not improve or alter the reported cold-to-live or time-to-tip figures:
the benchmark emits them before cleanup. This is a benchmark-turnaround
improvement, not measured end-to-end IBD acceleration. An unresponsive child
still consumes the shutdown grace period; scheduler load can extend polling.

The regression compiles the actual cleanup function. Its deterministic cases
cover an already-exited child, delayed graceful exit, forced shutdown, ECHILD,
interrupted waits and sleeps, and repeated cleanup. Forced termination occurs
at 500 ms both with ordinary sleeps and with every sleep interrupted halfway.
Wall-clock measurements are descriptive; only deterministic budgets gate.
The baseline passes the behavior/measurement mode and fails the new regression.

Reproduce with a saved pre-change benchmark source:

```bash
bash tools/scripts/bench_fresh_sync_cleanup_selftest.sh --baseline /tmp/before.c
bash tools/scripts/bench_fresh_sync_cleanup_selftest.sh
```

Baseline source SHA-256:
`3f94cab60bbb4303f37ae406a6297a68e1905f650871a07634e6ca7a792614e2`.
Changed source SHA-256:
`8e40155cd3b085f86013fdf18fc43c9b24814cd2dc715cb3e2c950b3fabafcf6`.

Validation and remaining limits:

- The focused fixture passes C23 compilation with `-Wall -Wextra -Werror
  -pedantic` and GCC `-fanalyzer`.
- Direct execution of all 15 fresh-sync scripts gives 14 passes. The timing
  script fails with `t_done=19` where it expects 21; its failure output is
  byte-identical against the saved baseline and changed source. No existing
  assertion was changed or weakened.
- Both full benchmark executables compile with the existing target flags.
  The same seven pre-existing warnings remain in both: five unchecked system
  calls and two potentially truncated copy commands. None is suppressed.
- `make bench-fresh-sync-selftest`, `make lint-fast` and `make lint` exceed 50-second
  bounds during setup, before their results. The node build cannot register
  the missing Tor submodule because Git metadata is read-only. These checks
  are not claimed green.
- Direct architecture-tree, pipefail-status, discarded-status and shell-host
  checks pass. Their tracked-tree scans do not cover the new untracked test;
  it separately passes Bash syntax and the compiled fixture checks.
- `git diff --check` passes, and consensus/reducer paths match HEAD.

The owned diff is cleanup in `tools/bench_fresh_sync.c`, one Make test
invocation, the new cleanup regression and this note. Review it against the
pre-slice working tree, not all existing changes in those shared files.
Consensus source, validation, acceleration policy, peer/request scheduling,
databases and node runtime are unchanged. No generated artifacts, secrets,
logs, caches, binaries or temporary measurements belong to this slice.

Publication remains incomplete: the initial fetch fails on read-only
`.git/FETCH_HEAD`; a later retry reports no remote `main` ref.
`origin/main` is absent locally, and the final query of the actual origin
development branch still fails to resolve the origin host. No commit, push or independent remote
SHA verification is claimed. Staging the two new files succeeds, but this
does not establish fetch or publication access. Publication requires working
fetch/origin access, separation from earlier work, and completion of the
outstanding validation without weakening its assertions.
