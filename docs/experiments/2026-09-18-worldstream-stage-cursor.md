<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream stopwatch stage-cursor observation

The cold-start stopwatch reads header-admission and body-persistence cursors
on every observable sync poll. Each read previously launched `tr` followed by
`awk`. Splitting each input line into brace-delimited fields inside awk removes
`tr`; a Bash here-string also removes the input pipeline. The two reads now
launch two external tools instead of four. This changes observation cost only:
the node, consensus, independent validation, optional acceleration, scheduling,
databases, thresholds and phase-boundary predicates are unchanged.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including the existing uncommitted
Worldstream work. Baseline stopwatch SHA-256:
`d0f3eb4e317914ea3de6d4ba9a0ce0c2433714c9130c33c4f34f19079e1c8e76`.
Updated stopwatch SHA-256:
`f631d5a9de3ee8a88078d2c998c84014bd9562b1414b60dc760e7e53040906a7`.
This slice changes only `frontier_stage_cursor`, adds its selftest invocation,
adds `tools/scripts/stopwatch_stage_cursor_selftest.sh`, and adds this note.
Other pending changes are outside the slice.

Measured on Linux x86_64, AMD EPYC 7402P, Bash 5.2 and GNU awk 5.2.1.
The fixture uses the same in-memory two-stage response for 500 poll pairs,
with warm executable caches and uncontrolled host load. No node, datadir,
network or sleep participates. Values are a single before/after observation;
wall time is informational, while process count is a deterministic gate.

| Measurement | Before | After |
|---|---:|---:|
| External tools per poll pair | 4 | 2 |
| Wall time, 500 poll pairs | 4.493 s | 3.471 s |
| User + system CPU | 6.886 s | 3.590 s |

These numbers do not establish an end-to-end IBD or time-to-tip gain.
Reproduce with `bash tools/scripts/stopwatch_stage_cursor_selftest.sh --bench`;
an optional final argument selects a saved baseline stopwatch. The baseline
passes value checks and fails the process budget. The fixture covers missing
stages, absent/null/string cursors, zero and negative values, similarly named
keys, duplicate records/keys, line boundaries and responses larger than a pipe
buffer. It preserves the existing compact-record parsing policy, including
which duplicate wins; this is not a general JSON parser. GNU awk and mawk pass.
A mutant replacing the missing-value sentinel with zero fails the fixture.

The stopwatch's full hermetic selftest, artifact-symmetry selftest and evidence
judge selftest pass. Shell syntax, whitespace, shell-host assumptions,
discarded-status, pipefail-status-pipe, no-API-keys, no-Python and architecture
checks pass. The core seal
verifies all 554 files and 80 section seals, and its exported root mirror
matches. No compiler changes or node build are needed for this shell-only
slice. No secrets, generated files, logs, binaries or benchmark output belong
to it.

Publication remains unavailable: Git metadata is read-only, `origin/main` is
absent locally, and the origin query fails on GitHub DNS. Commit, push and
remote-SHA equality are not claimed. `make lint` reached its 45-second bound
during prerequisite compilation after a zlib dependency download failed on
DNS. Full lint is incomplete; focused evidence is not a substitute for
publication gates.
