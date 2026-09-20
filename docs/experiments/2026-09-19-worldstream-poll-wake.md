<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: include interruption overhead in IBD polling intervals

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fresh-sync benchmark restarted interrupted sleeps using the kernel's
remaining duration. Time spent handling an interruption or waiting to be
scheduled after that duration was captured therefore extended the polling
interval. This delays the next sync-state observation and can add avoidable
sleep beyond the trial deadline. Recompute each retry from a monotonic wake
deadline. Normal two-second polling, failure handling, and acceptance criteria
are unchanged. An interruption itself can still overrun the deadline; the
observer now avoids sleeping again after its wake time has passed.

The baseline is the existing working source, SHA-256
`be9944a3c4f22492e1a3df46b2294417c1d401a5a88e9a0852f0acfc3e7a44ea`,
not pristine HEAD. Preserve all earlier staged, unstaged and untracked work.
This slice changes the polling delay, adds a regression to the existing
benchmark aggregate, and supplies a clock to the existing cadence fixture.
Entry snapshots and a separate review patch are in
`/tmp/worldstream-poll-wake/`.

## Reproduction

The fixture compiles the actual polling delay with GCC 14.2.0, C23, `-O2` on
Linux x86_64. A deterministic clock interrupts sleep after 125 ms, then adds
time outside sleep before returning the kernel's recorded remaining duration.
No node, network, real signals, credentials or datadir participate.

| Requested interval | Outside-sleep delay | Baseline elapsed | Candidate elapsed |
|---|---:|---:|---:|
| 2 s | 0 s | 2 s | 2 s |
| 2 s | 0.5 s | 2.5 s | 2 s |
| 2 s | 5 s | 7 s | 5.125 s |
| Final 0.5 s before deadline | 0 s | 0.5 s | 0.5 s |
| Final 0.5 s before deadline | 0.5 s | 1 s | 0.625 s |
| Final 0.5 s before deadline | 5 s | 5.5 s | 5.125 s |

These are deterministic observer-delay measurements, not end-to-end IBD or
time-to-tip speedups. Real interruption frequency and scheduling overhead have
not been measured. The baseline fails the new regression's elapsed-time
assertion; `--baseline` characterizes its old behavior.

## Validation

- `bash tools/scripts/bench_fresh_sync_poll_wake_selftest.sh` passes all six
  cases with `-Wall -Wextra -Werror -pedantic` and GCC `-fanalyzer`.
- Existing cadence and deadline regressions pass with static analysis,
  including repeated interruptions and permanent sleep errors.
- `make bench-fresh-sync-selftest` passes its complete aggregate and bootstrap
  and receipt prerequisites.
- The complete benchmark links with its existing target's flags. A stricter
  whole-file build fails on the same seven diagnostics in baseline and
  candidate: five ignored `system` results and two copy-command truncations.
- Shell syntax, architecture-tree, shell-host-assumption, pipefail-status,
  discarded-status, and `git diff --check` checks pass. The exact slice diff
  was reviewed. No generated interfaces change.
- `make lint-fast` exceeded a 50-second bound during initialization. No
  aggregate lint pass or publication readiness is claimed.

Consensus, validation semantics, optional acceleration policy, custody and
Hetzner-owned runtime, scheduling and database surfaces are unchanged. The
slice includes no secrets, production state, logs, caches, binaries or build
output. The public node binary is unavailable; no live-chain result is claimed.

Publication remains incomplete: fetch cannot write the read-only
`.git/FETCH_HEAD`, and remote lookup cannot resolve GitHub. No commit, push or
remote-SHA verification is claimed. Do not stage the complete dirty source or
Makefile as this slice; both contain extensive earlier work.
