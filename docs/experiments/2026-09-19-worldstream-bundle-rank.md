<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: defer metadata for lower-ranked bootstrap bundles

The time-to-tip probe scanned size metadata for every bundle candidate,
including candidates whose height could not beat its current eligible winner.
Move the existing size command and strict >10 MiB check into the replacement
branch. Numeric height ordering, lexical name fallback, first-wins equal-name
ties, missing-file checks and `.failed` exclusions remain unchanged. A proposed
winner still needs the same successful size check before replacing the old one.
This selects a benchmark input; it neither validates nor accepts chain state.

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The source checkout has substantial unrelated
staged and unstaged work. This slice was prepared independently from clean HEAD
in `/tmp/z23-worldstream-bundle-rank.TudeIn`, then its small source delta and
new regression were also applied to the original checkout. Flag-registry
first-use line references were refreshed for each checkout's actual lines.
Only this slice belongs in its commit.

## Reproduction and measurements

```sh
bash tools/scripts/cold_start_bundle_rank_selftest.sh --bench
# Optional final argument: saved baseline cold_start_to_tip_probe.sh.
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
```

Linux x86_64, AMD EPYC 7402P, Bash 5.2.21, GNU coreutils 9.4; warm filesystem
metadata and ambient host load. The private fixture uses 100 sparse files
above the size floor. A high bundle precedes 99 retained older candidates;
ten selections run per measurement. There is no node, peer, real bundle
content, RPC or production datadir. File creation is outside the timer.
The test counts actual size commands through a function forwarding to `stat`.

| Three paired runs, ten selections each | Before | After |
|---|---:|---:|
| Size commands per run | 1,000 | 10 |
| Wall seconds, run 1 | 7.445 | 3.634 |
| Wall seconds, run 2 | 7.444 | 3.619 |
| Wall seconds, run 3 | 7.378 | 3.654 |
| Median wall seconds | 7.444 | 3.634 |

This is a 99% reduction in size commands and approximately 51% lower fixture
selection time. Ascending eligible catalogs still need every size check.
No end-to-end IBD gain is established, and performance of predominantly tiny
ineligible catalogs is not claimed. Directory checks and name parsing remain.
The time figures are informational; command demand is the deterministic gate.

## Qualification

All 14 selection scenarios pass on old and new implementations: empty and
ineligible inputs, ascending/descending/mixed heights, equal-name ties across
directories, lexical fallback, failed candidates, exact-size boundary,
undersized highest candidates in either position, undersized first ties and
failed metadata. The old source fails the metadata-demand assertion. Removing
the size floor also fails the regression. The test is wired into the existing
probe `--selftest`, which is already used by the C3 Make acceptance wrapper.
The original dirty checkout's additional RPC-status and height-parser selftests
also pass with the slice applied.

Bash syntax, discarded-status, pipefail-status-pipe, shell-host-assumption,
architecture, flag-registry, no-Python and secret-scanning checks pass.
The byte seal verifies all 554 files and 80 sections. No compiled node code,
consensus, cryptography, block/transaction validation, activation height,
serialization, acceleration policy, peer scheduling, database or runtime
behavior changed. Normal independent validation remains authoritative.
ShellCheck and Clang are unavailable; this slice changes shell and source
metadata only. Temporary files, benchmark output, binaries and caches are
excluded from the commit.

All 32 `make lint-fast` gates pass using the existing fixture override:

```sh
mkdir -p .cache/windows-guard-scratch
ZCL_WINDOWS_ACCEPTANCE_GUARD_SCRATCH="$PWD/.cache/windows-guard-scratch" make lint-fast
```

The initial lint run exposed displaced flag references, fixed in this slice.
A subsequent run could not write the Windows guard fixture below the default
owner state directory; the documented scratch override above allowed its
unchanged checks to run. No thresholds or assertions were weakened.

Publication limitation: Git metadata in the original checkout is read-only.
The isolated repository retains the required development branch and real
GitHub origin. Fetch and remote observation fail because GitHub DNS is
unavailable; upstream integration and exact remote SHA equality remain
unverified. This report records local qualification, not publication or a
completed sync mission.
