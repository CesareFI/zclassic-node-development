<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stop starting observers after a poll expires

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The cold-start benchmark checked its deadline before and after each poll,
but a slow sync-state RPC could exhaust the budget and still trigger a height
RPC, phase-log scan and explorer fetch. This added observer work after the
trial was already late. The loop now checks the budget before those three
operations. Existing completion predicates, inclusive end-of-poll deadline,
first-tip timestamp and failed-run exit status remain unchanged. Skipped
height observations retain the unavailable sentinel.

This slice changes only three guards in `tools/bench_fresh_sync.c`, adds the
expired-observers selftest to `bench-fresh-sync-selftest`, and supplies the
production timeout definition to the existing height-only fixture. Earlier
staged, unstaged and untracked work remains intact. The source baseline is
the working file at entry, SHA-256
`0c077f264acdd86add5e53686771d4b733e79865c9180b2ec700ceb0c9ad049c`.
Baseline copies and the isolated modification patch are under
`/tmp/worldstream-expired-observers/`; these are temporary development evidence.

## Reproduction and measured work

Linux x86_64, GCC 14.2.0. The regression compiles the production polling loop
with deterministic observers and a simulated monotonic clock. Each observer
costs two simulated seconds; the trial budget is 30 seconds. There is no node,
network, chain data, production datadir or cache-sensitive I/O measurement.

| Expiry witness | Baseline subsequent height / log / page calls | Candidate calls | Baseline / candidate poll finish (simulated seconds) |
|---|---|---|---|
| State returns at 31 | 1 / 1 / 1 | 0 / 0 / 0 | 37 / 31 |
| Height returns at 31 | 1 / 1 / 1 | 1 / 0 / 0 | 35 / 31 |
| Log scan returns at 31 | 1 / 1 / 1 | 1 / 1 / 0 | 33 / 31 |
| State returns exactly at 30 | 1 / 1 / 1 | 1 / 0 / 0 | 36 / 32 |
| Failed state returns at 31 | 1 / 1 / 0 | 0 / 0 / 0 | 35 / 31 |

The baseline passes characterization with `--baseline` and fails the new
demand assertion without that option. The candidate passes all five cases.
These measurements establish removed observer calls, not faster real IBD.
An observation already in flight may still overrun. Final report diagnostics
and cleanup remain separate from this polling budget.

## Validation

```sh
bash tools/scripts/bench_fresh_sync_expired_observers_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_timing_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_poll_budget_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_height_selftest.sh --analyze
```

The extracted production-loop fixtures pass C23 `-Wall -Wextra -Werror`
compilation and GCC `-fanalyzer`. All `bench_fresh_sync_*selftest.sh` scripts
and `bench_sync_bootstrap_selftest.sh` pass, including 24 completion scenarios
and nine timing scenarios. The existing exact-deadline completion witness
continues to pass. The new test is wired into the aggregate Make target;
scripts were run directly because Make initialization is slow in this checkout.

The complete benchmark compiles and links with its existing target flags.
An additional strict full-file build fails on existing unchecked `system()`
results and copy-command truncation warnings; the saved baseline reproduces
those failures. No warning suppression or gate weakening was added.
`make lint-fast` times out after 50 seconds during initialization, so aggregate
lint remains unverified. Direct architecture-tree, discarded-status,
pipefail-status and shell-host-assumption gates pass. Shell syntax and both
staged and unstaged `git diff --check` pass. ShellCheck is unavailable.

Only benchmark tooling and this record changed in this slice. Consensus core
is clean against HEAD. No consensus, cryptographic semantics, optional
acceleration policy, Hetzner-owned runtime or scheduling code changed. The
reviewed slice contains no secrets, logs, binaries, generated files or caches.

Publication remains blocked: fetching cannot write `.git/FETCH_HEAD` because
`.git` is mounted read-only, and the exact remote branch lookup cannot resolve
GitHub. No commit, push, remote-SHA verification or live time-to-tip acceptance
is claimed. The branch is unchanged. Do not stage the entire dirty C source,
Makefile or pre-existing height fixture as this slice; they contain earlier
work. The lint and strict full-file compilation gaps remain explicit.
