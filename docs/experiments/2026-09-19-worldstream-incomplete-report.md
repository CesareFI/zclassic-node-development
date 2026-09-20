<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stop page diagnostics after incomplete sync benchmarks

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fresh-sync driver can observe explorer readiness, subsequently lose tip,
and exhaust its trial budget. Its final report still fetched four explorer
pages because historical readiness alone enabled those diagnostics. Each
fetch permits two seconds of HTTP waiting, adding up to eight seconds after
an already incomplete measurement and delaying benchmark-child cleanup.

Require the existing completion timestamp as well as observed readiness
before these four diagnostic fetches. Preserve completed-run page order,
partial milestone reporting, the independent validation-status RPC and the
unsuccessful exit status. The sync poll loop and its acceptance criteria do
not change.

## Reproduction and measurement

Baseline is the working source at session entry, SHA-256:
`316c415e466ad496817ee4475c92efd5081f11c278309718a9e09221877c00ce`.
Earlier uncommitted benchmark changes are prerequisites, not this slice.
Saved inputs and test output are under `/tmp/worldstream-incomplete-report/`.

Linux x86_64, GCC 14.2, strict C23 `-O2`. The existing report fixture compiles
the production report against counted HTTP stand-ins; no node, network or
production state is involved. Cache state and network topology do not affect
this deterministic call-count measurement.

| Trial outcome | Baseline page requests | Candidate page requests |
|---|---:|---:|
| Explorer never ready; incomplete | 0 | 0 |
| Explorer previously ready; incomplete | 4 | 0 |
| Completed | 4 | 4 |

All three cases run with successful and failed validation-status RPCs. That
RPC remains exactly one call in every case. The removed HTTP wait allowance
is eight seconds; this is a configured upper bound, not a measured wall-time
or end-to-end IBD improvement.

The strengthened report test fails on the saved baseline at the incomplete,
previously-ready case. Its `--baseline` mode reproduces the earlier counts.
The full polling fixture also asserts zero final page requests in all failed
trials and four in successful trials, including tip loss/recovery, missing
RPCs, late readiness and interrupted completion.

## Validation

- `bash tools/scripts/bench_fresh_sync_report_demand_selftest.sh --analyze`:
  six cases pass, including strict warnings and GCC static analysis.
- `bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze`:
  all 24 scenarios pass, including GCC static analysis.
- `make bench-fresh-sync-selftest` and `make bench_fresh_sync`: pass.
- Shell syntax and `git diff --check`: pass.
- Direct architecture-tree, shell-host-assumptions, pipefail-status and
  discarded-status checks (including the shell gate self-tests): pass.

`make lint-fast` and the grouped Make lint-gate invocation both exceeded a
60-second bound during initialization. The direct checks above provide
focused results, not an aggregate lint pass. Aggregate lint remains required
before publication.

Only the standalone benchmark, its existing regressions and this note belong
to the slice. No consensus, independent validation, acceleration policy,
peer scheduling, database or node-runtime behavior changes. `core/` matches
HEAD. Temporary output and binaries remain outside the proposed source diff;
no credentials, wallet material, generated output or production state is
included.

Publication remains blocked: fetching cannot write `.git/FETCH_HEAD` because
Git metadata is mounted read-only, and `git ls-remote origin` cannot resolve
GitHub. No upstream integration, commit, push or remote-SHA verification is
claimed. Preserve the pre-existing staged and unstaged work; committing the
entire dirty benchmark file would incorrectly include earlier slices.
The exact incremental source/test/doc patch is retained at
`/tmp/worldstream-incomplete-report/slice.patch` for review and continuation;
it is not an independently landable replacement for those prerequisites.
