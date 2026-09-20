<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fresh-sync benchmark deadline outcomes

The standalone fresh-sync benchmark returned success after timing out. Its
poll-entry deadline check also let an observation that finished late report
"Fully operational". These false successes prevent automated IBD comparisons
from distinguishing completed runs from budget misses. This change improves
measurement validity; it does not demonstrate faster chain synchronization.

The regression compiles the actual production poll loop, result reporting and
final return with deterministic observer and clock doubles. No node, network,
chain data, credentials or production datadir participates. The fixture uses
a 30-second budget and the existing greater-than-five-second tip grace period.

| Fixture | Baseline | Corrected |
|---|---|---|
| Normal completion | Exit 0 | Exit 0 |
| Tip never observed | Exit 0 after timeout | Exit 1 |
| Explorer never observed | Exit 0 after timeout | Exit 1 |
| Explorer completes at 31 s, tip at 23 s | Fully operational, exit 0 | No completion claim, exit 1 |
| First tip observed at 31 s | Exit 0 after timeout | Exit 1 |
| Explorer completes at 30 s, tip at 23 s | Fully operational, exit 0 | Fully operational, exit 0 |

The benchmark now rechecks its clock after observations, before accepting
completion, and returns failure when no completed run was recorded. Partial
phase observations and post-run diagnostics remain available. The deadline
remains inclusive. This is an acceptance deadline, not a strict process runtime
limit: individual observations, diagnostics and cleanup can still take longer.
The benchmark's existing readiness condition does not prove complete sovereign
validation; its separate validation-status report remains unchanged.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with existing pending Worldstream
changes. Baseline `tools/bench_fresh_sync.c` SHA-256:
`8d0de6679751468115ade036049be7dd0b9ba9d26be5efce4b465d91c0472000`.
Updated SHA-256:
`c23b6b649d0f5b58a2508295417cc22cc3f0d5e7ecac5e62b4eaaedbac7053ee`.
This slice owns only the two outcome checks and exit-status comment in that
file, the new outcome selftest, its one Makefile invocation and this note.
The fixture also uses the existing pending phase-observer work. Earlier staged
and unstaged changes are preserved; they are not part of this slice.

Reproduce:

```bash
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze
make bench-fresh-sync-selftest
```

An optional source path selects a saved baseline. On Linux x86_64 with GCC
14.2, the baseline fails four of six cases; the corrected code passes all six.
Removing either new check independently makes the regression fail. The real
loop and result path pass C23 `-Wall -Wextra -Werror` and GCC `-fanalyzer`.
Existing phase-log, command-output, HTTP-deadline and observation-timestamp
regressions pass directly, as do the stopwatch judge and artifact-symmetry
suites. The complete benchmark builds with its shipped compiler flags, with
the seven previously documented warnings outside this slice (five ignored
`system` results and two potentially truncated certificate-copy commands).

Architecture, shell syntax, discarded-status, pipefail-status, wall-clock-test,
secret, no-Python and shell-host-assumption checks pass. All 554 sealed core
files and 80 sections verify, and the root mirror matches. Exact diff inspection
and `git diff --check` pass. Consensus, independent validation, optional
acceleration, peer scheduling, database tuning and node runtime are unchanged.
No binaries, logs, datadirs or temporary benchmark output belong to this slice.

The Make selftest aggregate and `make lint-fast` each exceeded a 50-second
bound during setup before running their recipes; neither aggregate is claimed
green. The individual checks above ran directly. Publication is incomplete:
Git metadata is read-only, `origin/main` is unavailable locally, and querying
origin fails on GitHub DNS. No commit, push, upstream integration or remote-SHA
equality is claimed. The existing staged diff is byte-for-byte unchanged.
