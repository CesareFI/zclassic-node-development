<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream blocker-list observation cost

The cold-start stopwatch extracts blocker IDs on every synchronization poll.
Its `tr | grep | sed | paste` pipeline launched four external tools per read.
One awk invocation now produces the same comma-joined IDs, trailing newline,
and no-match exit status. Newline removal, empty IDs, duplicates and encounter
order are preserved. This remains the existing compact telemetry reader, not
a general JSON parser.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including pre-existing uncommitted
Worldstream changes. Baseline stopwatch SHA-256:
`14a752ad8412d510bdf6a13d61d38e148db5053995e4b644b50783f3bcbda44c`.
Updated stopwatch SHA-256:
`4fe2a0ae6d6976a185b0ddc5e50980c29425a299a35e56c5352c12a0bbcc396f`.
This slice changes only `blocker_ids`, wires its regression into the existing
stopwatch selftest, adds `tools/scripts/stopwatch_blocker_ids_selftest.sh`,
and adds this note. Existing unrelated work is preserved.

The benchmark runs 500 observations of a fixed two-blocker response in memory
on Linux x86_64 with GNU awk 5.2.1. Executable caches are warm; host load is
uncontrolled. No node, datadir, RPC, network or sleep participates.

| Measurement | Before | After |
|---|---:|---:|
| External parser tools per poll | 4 | 1 |
| Wall time, 500 polls | 1.968 s | 1.748 s |
| User + system CPU, 500 polls | 5.208 s | 1.806 s |

These are single-run observer-cost measurements, not evidence of an
end-to-end IBD or time-to-tip improvement. Wall time is informational; the
deterministic one-tool budget is the performance regression gate.
Reproduce with:

```bash
bash tools/scripts/stopwatch_blocker_ids_selftest.sh --bench
```

An optional final script-path argument selects a saved baseline stopwatch.
The baseline passes the value/status fixtures and fails the process budget.
Fixtures cover no matches, empty and duplicate IDs, whitespace/newlines,
similarly named keys, raw escape handling, large responses and 256 ordered
IDs. GNU awk and mawk pass. A mutation changing the no-match status to success
is rejected.

The complete hermetic stopwatch selftest, artifact-symmetry selftest and
evidence-judge selftest pass. Shell syntax, whitespace, shell-host assumptions,
discarded-status, pipefail-status-pipe, no-API-keys, no-Python and architecture
checks pass. The core seal verifies 554 files and 80 sections; its exported
root mirror matches. This shell-only slice changes no consensus, node runtime,
validation predicates, acceptance thresholds, optional-acceleration policy,
peer scheduling or database tuning. No compiler change or generated interface
update is needed, and no secrets or runtime artifacts belong to the slice.

`make lint-fast` exceeded its 45-second bound after template preparation;
the aggregate gate is incomplete. Publication is also blocked: `.git` is
read-only, so fetching fails at `.git/FETCH_HEAD`; `origin/main` is absent
locally; querying the exact development branch on origin fails on GitHub DNS.
No commit, push, upstream integration or remote-SHA equality is claimed.
