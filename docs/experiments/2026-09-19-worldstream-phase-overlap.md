<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream stopwatch overlap-report cost

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`, with pre-existing uncommitted Worldstream
work preserved. The measured `phase_overlap_json` function matched HEAD
before this slice. Linux x86_64, Bash 5.2.21, local synthetic phase intervals,
ordinary warm filesystem caches and ambient load; no node or network ran.

The cold-start stopwatch recomputed each phase span inside each overlap pair.
Four observed phases required 16 command-substitution subprocesses per report.
A report-local associative array retains the four spans already evaluated for
the sum. Pair comparisons reuse those values. Each new report still reads the
current boundaries; no observation survives across reports.

| Measurement | Before | After |
|---|---:|---:|
| Span subprocesses per four-phase report | 16 | 4 |
| 200 reports, wall seconds | 6.417 | 3.504 |
| 200 reports, user seconds | 1.655 | 1.000 |
| 200 reports, system seconds | 5.986 | 3.461 |

One trial per version; elapsed times are informational. The deterministic
regression checks four span evaluations, observed overlap arithmetic, missing
edges, reversed intervals, instant phases, disjoint intervals, and freshness
across successive reports. The baseline passes value assertions and fails the
four-evaluation budget. This is artifact-reporting overhead, not a measured
end-to-end IBD or time-to-tip improvement.

Reproduce with `make stopwatch-overlap-selftest ARGS=--bench`, or
`bash tools/scripts/stopwatch_overlap_selftest.sh --bench`. An optional final
argument selects a baseline stopwatch script. No node build is required.

Validation completed:

- Focused regression and Make target pass.
- Full `cold_start_to_tip_stopwatch.sh --selftest` passes.
- `stopwatch_artifact_symmetry_check.sh --selftest` passes.
- Benchmark bootstrap and epoch checks pass (43 and 46 cases).
- An independent comparison of 256 combinations of missing, instant, and
  overlapping phase intervals produces byte-identical old/new reports.
- Bash syntax, architecture, pipefail-status and shell-host-assumption gates
  pass. `git diff --check` passes.

Only shell reporting, its fixture, and standalone Make wiring change. No
consensus, validation, acceleration, peer scheduling, database, wallet or
production-state behavior changes. This slice contains no generated artifacts,
credentials, logs or binaries; test output remains under `/tmp`.

Publication is incomplete: `.git` is mounted read-only, so fetch and staging
fail; the remote lookup also fails because GitHub DNS is unavailable. No
commit or push was made, and no remote SHA match is claimed. Existing staged
work is byte-identical to the entry snapshot. The full parallel `lint-fast`
attempt was interrupted after making no visible progress beyond template
generation. A serial retry (`timeout 60 make ZCL_LINT_SERIAL=1 lint-fast`)
also timed out there (exit 124); focused gates above are not a claim of full
lint acceptance.
