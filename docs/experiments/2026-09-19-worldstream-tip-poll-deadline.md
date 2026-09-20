<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound the final time-to-tip polling sleep

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The cold-start time-to-tip probe slept five seconds after every unsuccessful
sample, even when observation work had consumed most or all of the trial
budget. This delayed failure reporting and kept the isolated child running
beyond the requested observation window. The loop now refreshes its existing
clock before sleeping, stops when the budget is exhausted, and limits the
sleep to the smaller of five seconds and the remaining budget.

The regression extracts the actual polling loop and supplies an in-process
clock, sleep, and RPC doubles. Linux x86_64, Bash; no node, network, chain data,
or actual sleeps. These are simulated elapsed seconds, not end-to-end IBD
speedup measurements:

| Scenario | Budget | Entry elapsed | Candidate elapsed |
|---|---:|---:|---:|
| Short trial | 1 | 5 | 1 |
| Partial final interval | 6 | 10 | 6 |
| Ordinary cadence | 10 | 10 | 10 |
| Each RPC consumes two seconds | 10 | 14 | 10 |
| RPC exhausts budget | 2 | 2 | 2 |
| Seed observation exhausts budget after RPC | 4 | 9 | 4 |

The new regression fails against the entry source and passes all six cases
against the candidate. It is wired into the existing probe `--selftest` gate.
The RPC-status test now requires failed trials to finish at ten rather than
twelve seconds, retaining its verdict and failed-height assertions. The
height-parser test stops extraction before the new sleep-budget block.

Validation passed:

```sh
bash tools/scripts/cold_start_poll_deadline_selftest.sh
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
bash tools/scripts/cold_start_snapshot_metadata_selftest.sh
bash tools/scripts/cold_start_snapshot_metadata_selftest.sh --cold-start
bash tools/scripts/cold_start_bundle_name_selftest.sh
bash tools/scripts/cold_start_bundle_height_selftest.sh
```

Shell syntax, architecture-tree, pipefail-status, discarded-status,
shell-host-assumption, and `git diff --check` checks pass. ShellCheck is absent;
no compiled source changed. Both `make cold-start-snapshot-metadata-selftest`
and `make lint-fast` exceeded a 45-second initialization bound; their direct
focused checks above passed, but full lint is not claimed.

The existing seconds-resolution wall clock, RPC cancellation grace, process
scheduling, and teardown costs remain separate limitations. This change bounds
the requested ordinary polling sleep; it does not establish a hard runtime
deadline, change the respawn path, or alter time-to-tip acceptance predicates.
Consensus, validation, optional acceleration, peer scheduling, database tuning,
wallet custody, and production state are untouched.

Existing dirty work is preserved. Entry probe SHA-256:
`819089880b9266920c1555d6f017e121ef04d4e4624d448f243e083512e6cddd`.
Entry copies and a diff limited to this run are in
`/tmp/worldstream-tip-poll-deadline/`. The related pre-existing tests were
untracked at entry; the diff is relative to that working tree, not a standalone
patch against HEAD. Do not stage whole dirty files as this slice.

Publication is blocked: fetching cannot write `.git/FETCH_HEAD` (read-only
filesystem) and GitHub DNS resolution fails. Staging the new deadline test
succeeded, but restoring that file's unstaged state was refused because
`.git/index.lock` is read-only. That new test remains staged; no unrelated
index entries were changed. With integration and full lint incomplete, no
commit or push was attempted. No remote SHA was verified. No generated output,
credentials, logs, binaries, or datadirs are part of this slice.
