<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fold-profile regression startup

Owned surface: Makefile selection for the two isolated fold-profile test
targets, and additional cases in the existing benchmark bootstrap regression.
This improves the IBD instrumentation development loop, not measured chain
download speed. No node, peer or production datadir participates.

The branch remains `agent/worldstream-ibd-20260918`, at
`c1f7863d098e1efaa8deba240c580ae0559312a5`. There was extensive staged,
unstaged and untracked work at entry. In particular, both fold-profile
targets and the bootstrap regression already existed in the working tree.
The baseline is that working tree, not pristine HEAD. Prior work is preserved.

## Witness and change

`make -n fold-profile-selftest` exceeded a 20-second bound before displaying
its recipes. The expanded regression, using the production Make conditionals
and inert vendor/Tor marker recipes, fails against the saved baseline with
`goals=[fold-profile-selftest] expected=[none] observed=[vendor ]`.
These shell/awk fixtures need neither vendor archives nor node/test object
epochs, but were absent from the standalone benchmark goal list.

Extend that exact allowlist with `fold-profile-selftest` and
`fold-profile-summary-selftest`, rename it to describe both sync benchmark
families, and require the bootstrap regression from both targets. Default,
unknown and mixed node goals retain their prerequisites and profiles. Source
capture, validation and publication admission are unchanged.

## Measurement and validation

Linux x86_64, AMD EPYC 7402P, GNU Make 4.3, GCC 14.2.0, missing vendor/Tor
archives; ordinary filesystem caches and uncontrolled host load. Single-run
wall timings, not distributions or end-to-end IBD/time-to-tip evidence:

| Invocation | Result | Wall time |
|---|---|---:|
| Baseline `make -n fold-profile-selftest` | Timeout | 20.00 s bound |
| Revised `make -n fold-profile-selftest` | Pass | 6.01 s |
| Revised `make fold-profile-selftest fold-profile-summary-selftest` | Pass | 8.73 s |
| Revised `make bench-fresh-sync-selftest` | Pass | 30.39 s |
| Revised `make lint-fast` | Setup timeout, no verdict | 45.00 s bound |

The dry-run timing preceded adding the bootstrap regression dependency; the
actual acceptance timing includes it. The regression passes 43 bootstrap and
46 epoch-selection cases. Cases include each standalone goal, explicit dev
profile, mixed goals in both orders, unknown goals, explicit vendor repair,
the default build, node builds and `bench-sync`. Fold-profile acceptance
includes exact CSV, 35 RPC refusals and recovery, bounded parser work, wide
durations, and long-history summaries under GNU awk, BusyBox awk and mawk.

Bash syntax, architecture-tree, shell-host-assumption, pipefail-status and
discarded-status checks pass, as does `git diff --check`. No C implementation
changed; no new compiler/static-analysis claim is needed for this Make/shell
slice. ShellCheck is unavailable. Full lint remains incomplete.

Baseline snapshots and the isolated incremental patch are temporary files
under `/tmp/worldstream-fold-bootstrap/`, not commit content. Makefile baseline
SHA-256: `ea31bac8616cc4c7559551d69d5bae5e846cecb560fb14ae36672de40c45b52b`.
Revised: `7e47e9dd23e8b320d5bdeb52739a34e69c13220a951381d0efa4383591af050b`.
The exact incremental diff was reviewed. Tracked status is unchanged from
entry; no core file differs in either the index or worktree. This slice changes
no consensus, validation, optional-acceleration policy, scheduling, database,
custody or node-runtime behavior. It includes no secrets, logs, binaries,
datadirs, caches or generated artifacts.

## Publication boundary

Fetch fails because `.git/FETCH_HEAD` is read-only. The development branch's
remote lookup fails resolving GitHub; `origin/main` is unavailable locally.
No commit, push, upstream integration or exact remote-SHA verification was
possible. The slice remains local and is not declared publication-ready.
The supervisor must preserve earlier work, complete integration/lint and
publish only to the designated development branch. Do not stage the whole
Makefile or bootstrap script as this slice: both include prior pending work.
