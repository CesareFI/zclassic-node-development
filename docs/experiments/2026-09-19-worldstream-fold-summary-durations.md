<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: preserve long IBD stage durations in fold summaries

The fold profiler formatted stage and total microseconds with awk `%d`.
BusyBox awk on this host narrows that conversion to a signed 32-bit integer:
a positive 2,147,483,648 microsecond stage was reported as -2,147,483,648.
A stage crosses that boundary after about 35.8 minutes, inside the default
one-hour profiling window. This prevents reliable interpretation of the
dominant sync stage on affected hosts. GNU awk and this host's newer mawk
do not exhibit that conversion failure.

The summary now uses `%.0f` for its two duration columns. The same regression
also exposed a mawk syntax refusal at a newline in the existing durability
barrier ternary expression; keeping that expression on one line fixes it.
Sampling, CSV schema, counter differences, shares, per-block rates, and
missing-measurement behavior are unchanged. Arithmetic still uses awk's
numeric representation; this is not a claim of exact full-range uint64
arithmetic. Non-duration counter formatting is outside this slice.

## Baseline and reproducible witness

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. Both clean HEAD and the working summary at
entry reproduce the defect. Existing staged, unstaged, and untracked work is
preserved. The isolated candidate includes only this renderer fix, its test,
its Make target, and this report.

Host: Linux x86_64; GNU awk 5.2.1, mawk 1.3.4 (20240123), BusyBox 1.36.1.
The regression extracts the actual summary program and CSV header from the
harness. Three synthetic cumulative samples start at a nonzero baseline;
their first-to-last differences straddle the signed 32-bit boundary, include
a two-hour stage, and extend to 2^41 microseconds. No node, RPC, network,
credentials, or datadir is used.

| Observation | Before | After |
|---|---:|---:|
| BusyBox stage delta, expected 2,147,483,648 us | -2,147,483,648 | 2,147,483,648 |
| BusyBox total, same fixture | -2,147,483,648 | 2,147,483,648 |
| mawk summary execution | syntax error | succeeds |
| GNU awk summary assertions | pass | pass |

This is a measurement-correctness improvement, not an observed end-to-end IBD
speedup. A real authorized sync profile is still needed to identify and price
the next runtime bottleneck.

## Validation

```sh
sh tools/scripts/fold_profile_summary_selftest.sh
make fold-profile-summary-selftest
```

The direct regression passes on all three installed awk implementations. It
checks differences rather than absolute counters, totals, shares, call and
advance counts, zero durations, idle intervals, and fewer than two samples.
The old source fails the same regression. An optional script-path argument
allows reproducing that comparison. The existing working-tree fold-profile
CSV, RPC-refusal, profile-scan, and drive-scan selftests also pass.

POSIX shell and Bash syntax, architecture-tree, shell-host-assumption,
discarded-status, pipefail-status-pipe, and whitespace checks pass. The
consensus seal verifies all 554 files and 80 sections. No compiled source,
consensus predicate, validation semantics, acceleration policy, peer/request
scheduling, database tuning, or node runtime behavior changes.

The aggregate `make fold-profile-summary-selftest lint-fast` attempt exceeded
a 50-second bound during Make initialization, with missing Tor archives and
unchanged template generation reported. Aggregate lint and Make dispatch are
not claimed green; direct tests and individual checks above are the evidence.

Only source and this report belong in the commit. Generated files, binaries,
logs, credentials, caches, and temporary CSV output are excluded. The original
checkout's Git metadata is read-only; the isolated candidate lives at
`/tmp/z23-worldstream-summary-slice.UCLYqu` on the required branch. GitHub DNS
fails for both fetch and remote-head observation. Upstream integration,
publication, and remote SHA equality remain unverified.
