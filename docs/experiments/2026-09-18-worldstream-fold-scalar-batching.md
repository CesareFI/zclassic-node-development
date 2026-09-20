<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fold-profiler scalar batching

The remaining drive/frontier scalar readers launched 18 external parser
processes per sample: nine `sed | head` pairs. They now use two awk processes,
one per response. This reduces the observer cost of measuring sync stages.
No node runtime, peer scheduling, storage tuning, validation, consensus, or
optional-acceleration policy changes are part of this slice.

The baseline is the existing Worldstream working copy on
`agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including prior uncommitted
profile/stage batching. This is not a clean-HEAD comparison. Baseline profiler
SHA-256: `377c04105e3af926b5bc473dc22fe1f5722aabb6b0c359ac586d70c66f64e476`.
Updated profiler SHA-256:
`266efe976a287267d0f9526d77a966540bea19a518539d3d3b56ced3a2072689`.
Pre-existing changes remain in place; this slice changes only the profiler,
its existing fixture, and this note.

Measured on Linux x86_64, AMD EPYC 7402P, GNU awk 5.2.1. The existing
hermetic benchmark runs 20 complete 50-column samples with shell RPC doubles
and a fixed timestamp. Filesystem caches are warm and host load uncontrolled.
There is no node, peer, datadir, network, or sleep in this measurement.

| Measurement | Before | After |
|---|---:|---:|
| External parser processes per sample | 22 | 6 |
| Wall time, 20 samples | 1.27 s | 0.68 s |
| User + system CPU, 20 samples | 1.81 s | 0.75 s |

This measures instrumentation overhead only, not time to tip. Wall time is
informational; the deterministic six-process ceiling is the regression gate.
Reproduce with `sh tools/scripts/fold_profile_selftest.sh --bench` or
`make fold-profile-selftest ARGS=--bench`. A final script-path argument selects
a saved baseline. The extended fixture passes the baseline's output assertions
and fails its process ceiling. Both GNU awk and mawk pass the updated fixture.

The scalar reader preserves the last integer on the first matching line,
missing-value zeros, exact wide/negative/leading-zero integer text, CSV column
order, and the sampling timestamp's position before parsing. Stage-profile
counters retain their separate first-integer policy. New cases cover duplicate
keys across and within lines, null/string values, and similarly prefixed keys.
A mutation selecting the first same-line scalar fails the regression.

The artifact-symmetry and stopwatch-judge selftests, POSIX and Bash syntax,
architecture, shell-host assumptions, pipefail-status-pipe, discarded-status,
no-API-keys, no-Python, no-warning-suppression and whitespace checks pass.
The core seal verifies all 554 sealed files and 80 section seals unchanged.
No secrets, binaries, benchmark output, caches, or generated files are part of
this slice.

Publication is blocked. Fetch cannot write the read-only `.git/FETCH_HEAD`;
`origin/main` is absent locally, and querying the exact development branch
on origin fails because GitHub DNS is unavailable. Full `make lint` hit its
45-second bound during prerequisite compilation after a dependency download
failed on DNS. The focused Make target did run and pass despite that same
download failure during preparation. Full publication gates, commit, push,
and exact remote-SHA verification are not claimed.
