<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fold-drive observation batching

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold profiler parsed every captured `reducer_drive` response twice:
scalars in one awk process, stage triples in another. The existing scalar
reader now optionally reads stage triples in the same process. Shell `read`
places those fields into the unchanged 50-column CSV. The stage-only helper
delegates to that reader, removing its duplicate scanning code.

This changes external IBD measurement overhead only. Consensus, mandatory
independent validation, optional Z23 acceleration, node runtime, peer/block
scheduling, database behavior and custody are unchanged. No live node,
production datadir, chain data or network peer was used.

## Baseline and measurement

The baseline is the dirty working script at session entry, including earlier
pending Worldstream changes, not clean HEAD. Its SHA-256 is
`e71d95bc708738cd931a7e8160a2f12ecdbf003ea61af81552b52ff11978bc1e`.
The resulting script's SHA-256 is
`10f0bbb1c75c8f78de1204ee8ad8e6049a4a02782bd6694955a6f06992f8f882`.

Linux x86_64, AMD EPYC 7402P, dash and GNU Awk 5.2.1. Each timing covers
200 complete sampler calls with synthetic RPC responses, a fixed timestamp,
temporary CSV output and warm tool/filesystem caches. Three alternating
baseline/candidate runs used the same fixture. Ambient host load was not
controlled; other local checks overlapped parts of the run.

| Measurement | Before | After |
|---|---:|---:|
| Parser processes per sample | 6 | 5 |
| Wall seconds, run 1 | 6.24 | 5.42 |
| Wall seconds, run 2 | 6.33 | 5.46 |
| Wall seconds, run 3 | 6.23 | 5.44 |
| Median wall seconds | 6.24 | 5.44 |

The fixture observer time fell about 13%. This is not an end-to-end IBD or
time-to-tip result. Real RPC latency and validation cost remain unmeasured.
The deterministic regression checks output and process count, not wall time.

## Reproduction and validation

```sh
sh tools/scripts/fold_profile_drive_selftest.sh --bench
sh tools/scripts/fold_profile_selftest.sh
sh tools/scripts/fold_profile_rpc_selftest.sh
sh tools/scripts/fold_profile_scan_selftest.sh
```

The new test accepts a saved baseline script as its final argument. Baseline
and candidate produce the same fixture CSV; baseline fails the five-parser
budget. Coverage includes scalar/stage duplicates, first matching lines,
missing fields, malformed stage objects, repeated requested fields, negative
scalars, leading zeros and wide integer text. Swapping opened/committed columns
in a temporary mutant fails the regression. Existing tests cover both stage
schemas and 15 RPC failure cases plus recovery. The focused tests also pass
with mawk; the new test passes under Bash. POSIX/Bash syntax checks pass.

Architecture, shell-host-assumptions, pipefail-status-pipe, consensus-parity
and core-seal-root-mirror gates pass. Direct core-seal verification matches
all 554 files and 80 sections. `git diff --check` passes. No compiled source
changed; ShellCheck is unavailable. Git-index-based gates do not include the
new untracked test, which was checked directly.

`make fold-profile-selftest lint-fast ZCL_LINT_SERIAL=1` timed out after 45
seconds during build initialization, before its test recipes ran. Running
the 32 lint-fast gates through `tools/lint/run_lint.sh` completed: 28 passed;
root hygiene rejected the existing `.agents`/`.codex` directories, complexity
rejected existing `tools/bench_fresh_sync.c` changes, and flag-registry found
27 stale first-use line pointers outside this slice. Windows guard fixtures
initially could not write their default scratch directory; rerunning with
the supported `ZCL_WINDOWS_ACCEPTANCE_GUARD_SCRATCH` override under `/tmp`
passed its seven selftests and tree scan. Overall lint remains failing.

## Owned change and publication

This slice owns only the combined reader/caller changes in `fold_profile.sh`,
one new invocation in the existing Makefile `fold-profile-selftest` target,
`fold_profile_drive_selftest.sh`, and this note. Other pending changes and the
existing index were preserved. Do not commit all changes in either shared
file as this slice. Temporary baselines, mutations, timings and logs remain
outside the proposed source changes. No secrets, binaries, build artifacts
or production data are part of this slice.

Publication is incomplete: `git fetch origin main` cannot write read-only
`.git/FETCH_HEAD`, and origin's development-branch query cannot resolve
`github.com`. No upstream integration, commit, push or remote-SHA equality
is claimed. The branch and HEAD remain unchanged.
