<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: do not launch a replay after a failed capacity query

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The guard was clean at session entry;
the checkout contained extensive unrelated staged and unstaged work.

The nightly/weekly replay benchmark guard checks for active mint folds before
starting a CPU/IO-heavy replay. It discarded a failed `systemctl` status. When
the user-manager query failed without stdout, it launched the replay anyway.
This can admit competing evidence work when the guard cannot observe capacity.
The change preserves the existing skip contract on query failure: exit zero,
an explicit `mint_query_failed` reason, and no replay execution or new sentinel.
Successful empty queries still execute the replay with its exact argv and exit
status; active mint units and missing systemctl still skip.

## Reproduction and measurement

Run `bash tools/scripts/replay_canary_guard_selftest.sh`. An optional argument
selects an older guard for the same regression. The test copies that guard
beside a replay double and supplies private systemctl/logger doubles; no real
node, service, datadir or network participates.

For a failed query with status 1 and empty stdout, the baseline launches one
replay; the candidate launches zero. The baseline fails the regression with
`query unavailable/occupied but replay launched`. The candidate passes failure
statuses 1, 3 and 127 with both empty and partial output, as well as normal
admission, argument/status preservation, active mint refusal and missing-tool
refusal. This is an admission-count measurement, not measured live contention,
IBD throughput or time-to-tip improvement. The pre-existing guard remains a
single observation, so work starting after that observation can still race it.

## Validation and boundaries

- Focused admission regression and Bash syntax checks pass.
- Adjacent replay parser tests pass: 23 output/status cases, 13 verdict
  scenarios, 29 amount cases and 26 string cases. These exercise the existing
  working-tree parser changes; those changes are not part of this slice.
- Discarded-status, pipefail-status, shell-host-assumption, architecture-tree
  and no-Python gates pass. The shell scans include the new staged regression.
- The core seal check passes for all 554 sealed files and 80 sections.
- `git diff --check` passes. The reviewed slice contains only the guard,
  regression script and this record. No secrets, generated files, logs,
  binaries, caches or production state are included.

No C source, consensus predicate, cryptographic validation, optional
acceleration policy, peer scheduling, database tuning or node runtime changes.
ShellCheck is unavailable; no C compiler check is applicable to this shell-only
slice. `timeout 240 make lint` exits 124 during initialization, after template
checks report unchanged outputs. No full lint pass is claimed.

Publication is incomplete. An initial fetch confirmed the development branch
matched origin; a later fetch could not write `.git/FETCH_HEAD`, and a remote
head lookup could not resolve GitHub. Staging the guard and regression
succeeded, but staging this record failed with a read-only `.git/index.lock`
error. The three-file commit attempt therefore failed on the unstaged new
record. HEAD remains the baseline SHA; no push or final remote-SHA verification
is claimed. The unrelated index patch was compared byte-for-byte with its
entry snapshot and remains intact. Temporary baseline, lint output and the
isolated three-file patch live under `/tmp/worldstream-replay-guard/` and are
not repository deliverables.
