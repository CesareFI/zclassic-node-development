<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: preserve IBD observer cadence across signals

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fresh-sync benchmark ignored the return from its two-second `usleep`.
An interruption therefore started another RPC/log observation immediately.
This adds observer work while the node is synchronizing and makes sampling
frequency depend on signals. Permanent sleep errors could remove the delay
entirely.

The delay now uses `nanosleep`, retries only the remaining interval after
`EINTR`, and reports other errors before returning failure. Normal cadence,
observation timestamps, grace requirements and completion criteria remain
unchanged. The new regression runs through `make bench-fresh-sync-selftest`;
two existing main-loop fixtures use the new sleep interface.

The baseline is the already-modified working source at entry, SHA-256
`1821a73e6c50ad6c1d6ad76e5eb9e89394ffd98b6022ba3aca693dcc193a2458`,
not pristine HEAD. Existing staged, unstaged and untracked work is preserved.
Entry snapshots and this slice's separate patch are under
`/tmp/worldstream-poll-cadence/`, outside the repository's deliverables.

## Reproduction and measurements

Linux x86_64, GCC 14.2.0. The fixture compiles the actual polling delay with
deterministic sleep responses; no real node, network, datadir or wall-clock
performance threshold participates. Twenty delays represent twenty observer
intervals. Interruptions arrive after each 125 ms while more time remains.

| Fixture | Baseline simulated duration | Candidate simulated duration |
|---|---:|---:|
| Twenty normal intervals | 40 s | 40 s |
| Twenty intervals with interruptions | 2.5 s | 40 s |
| Permanent sleep error | Twenty errors ignored | First error refuses |

The interruption fixture reduces unintended sampling frequency by 16 times.
This is deterministic observer-demand evidence, not measured end-to-end IBD
or time-to-tip improvement. It does not establish signal frequency on a host;
without interruption, sampling frequency is unchanged.

```sh
bash tools/scripts/bench_fresh_sync_cadence_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_timing_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze
make bench-fresh-sync-selftest bench-fresh-sync-height-selftest
make bench_fresh_sync
```

All commands above pass. Passing the entry source as the final argument to
the cadence regression fails the interrupted-duration assertion; adding
`--baseline` reproduces the old counts. Focused fixtures compile with C23,
warnings as errors and GCC static analysis. Architecture-tree, shell syntax,
pipefail-status, discarded-status, shell-host-assumption and `git diff --check`
checks pass. The exact slice diff was inspected for unrelated work and secrets.

Full-source strict compilation is still blocked by the same seven diagnostics
in baseline and candidate: five ignored `system` results and two potentially
truncated copy commands. Full-source static analysis also stops on the latter
diagnostics. `make lint-fast` exceeded a 50-second bound during initialization;
no aggregate lint pass or publication readiness is claimed.

Consensus, node validation, optional acceleration policy, and Hetzner-owned
scheduling, database and runtime behavior are unchanged. Only benchmark delay,
fixtures, test registration and this record belong to the slice. No secrets,
production state, binaries, logs or generated artifacts belong to it.

Publication is incomplete: fetching cannot write `FETCH_HEAD` (read-only
filesystem); remote lookup also fails because GitHub DNS is unavailable.
An intent-to-add entry for the new regression succeeded, so this is not a
claim that every Git metadata operation is blocked.
No commit, push or exact remote-SHA verification is claimed. Do not stage the
whole dirty benchmark, Makefile or pre-existing untracked fixtures as this
slice: they contain earlier work that needs separate integration.
