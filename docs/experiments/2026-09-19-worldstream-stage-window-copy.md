<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound fold-profile stage-window copies

Scope: `jnums` in `tools/scripts/fold_profile.sh`, its hermetic regression,
and registration in `make fold-profile-selftest`. No node implementation,
consensus, validation, scheduling, database, or acceleration policy changes.
This is an observer allocation improvement, not measured time-to-tip evidence.

The existing observer bounded stage regex input at the first closing brace,
but first copied the entire remaining telemetry line into `rest`. With large
diagnostic tails this unnecessarily allocated about one response per stage.
Start at 128 bytes and double only until the first closing brace or line end.
Wide counters, malformed/nested objects, duplicate policy, missing values, and
the historical comma-terminated incomplete-object behavior remain covered.

Baseline was the existing dirty working tree at HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, not that commit alone.
The pre-edit `fold_profile.sh` SHA-256 was
`5f7e5efd05d88b5efceda8b51b7d9f759b773db0d55496e62243bd1782b330e6`;
the changed script is
`354e064e3a8509a4d5d4ec02c8ffe25658ba9871dbf06518978cc2eb0c4a9a61`.
Existing unrelated edits were preserved.

On Linux x86_64 with GNU awk 5.2.1, the new regression instruments the real
reader's window substrings, measuring returned bytes without changing its
match state. One stage followed by synthetic diagnostic fields gives:

| Trailing fields | Before copied bytes | After copied bytes |
| ---: | ---: | ---: |
| 0 | 43 | 43 |
| 500 | 10,327 | 128 |
| 50,000 | 1,227,831 | 128 |

The new gate fails on the pre-edit reader and passes on the changed reader.
GNU awk, mawk, and BusyBox awk pass this regression and the existing stage-object
regression. No network, peers, or datadirs participate.

An uninstrumented run of the existing stage-object benchmark (100 reads,
four stages, warm tool/filesystem caches, uncontrolled host load) measured
3.01 seconds before and 2.94 seconds after at 50,000 diagnostic fields.
That single pair does not establish a throughput gain; line ingestion and
duplicate-key searches still scale with response size. The deterministic
claim is reduced stage-window copying, not bounded total parser work.

Reproduce the allocation regression and optional observer timing with:

```sh
sh tools/scripts/fold_profile_stage_window_selftest.sh
sh tools/scripts/fold_profile_stage_window_selftest.sh --bench
sh tools/scripts/fold_profile_stage_window_selftest.sh --baseline /path/to/pre-edit.sh
make fold-profile-selftest fold-profile-summary-selftest
```

The combined profiling and summary target passed, including exact 50-column
CSV observations, RPC failure/deadline behavior, parser budgets, and summary
arithmetic across GNU awk, mawk, and BusyBox awk. Shell syntax,
`git diff --check`, discarded-status, pipefail-status-pipe, and architecture
checks passed. `make lint` was interrupted during its prerequisite development
build before any full gate verdict; full lint remains incomplete. These focused
results alone do not qualify publication. No C compilation change is involved.

The session could not fetch: `.git/FETCH_HEAD` is read-only, and a separate
`git ls-remote origin refs/heads/agent/worldstream-ibd-20260918` failed because
GitHub DNS resolution is unavailable. No commit, push, or remote-SHA
verification is claimed.
