<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: crypto performance gate evaluation overhead

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. This slice improves reproducible benchmark
tooling for the cryptographic primitives used during chain validation. It
does not measure or claim an improvement in IBD throughput or time to tip.

The standing crypto performance gate launched four to six awk processes per
primitive to calculate its ratio, ratchet ceiling and verdict. One awk
invocation now performs that work. Both existing four-decimal rounding steps,
thresholds, verdict precedence, ratio formatting and exit statuses remain.
No performance baseline, measurement command or cryptographic code changes.

## Reproduction and measurement

Linux x86_64, Bash, GNU awk 5.2.1, warm tools, uncontrolled ambient host load.
Synthetic evaluator rows only: no node, network, chain data, wallet or production
datadir. Build/lint activity overlapped some runs; wall times are illustrative,
while process counts are deterministic.

The regression wraps awk and counts actual invocations. The original nine-case
selftest took 45 processes; the candidate took nine. The expanded 17-case test
also passes with the original evaluator, but its process budget fails: 84
processes versus the candidate's 17.

For timing, combine the original evaluator and its arithmetic helpers from
the base revision with the candidate's expanded selftest body. This holds all
17 test rows, ratio checks and status checks constant. Run baseline then
candidate sequentially for 50 selftest executions, repeated three times:

| Run | Baseline seconds | Candidate seconds |
| --- | ---: | ---: |
| 1 | 16.358 | 3.535 |
| 2 | 16.630 | 3.564 |
| 3 | 16.404 | 3.254 |

Median wall time fell about 78%; arithmetic process count fell about 80%.
This is benchmark evaluation overhead, separate from primitive execution time.

## Validation

`make crypto-perf-evaluator-selftest` runs the 17 exact-output/status cases,
the one-process-per-row budget, and five complete gate invocations using a
synthetic benchmark executable and CSV baseline. The five invocations cover
both successful verdicts and all three failure verdicts through real report
generation and process exit. All pass under GNU awk, mawk and BusyBox awk.
Boundary cases include equality and excess at the ratchet and Rust comparison,
display-only ratio rounding, margin rounding, product rounding and zero Rust
reference handling.

Shell syntax, shell-host-assumption, pipefail-status, discarded-status,
architecture-tree and `git diff --check` checks pass. ShellCheck is not installed.
No compiled source changes; no live crypto performance or chain acceptance
result is claimed.

The main checkout contained unrelated staged and unstaged work and read-only
Git metadata. Development and checks used a clean temporary clone of the exact
branch base. Only the gate, its fixture script, Make target and this report
belong to this slice. No logs, generated outputs, binaries or private material
belong in the commit. Consensus, independent validation, optional acceleration
policy and Hetzner-owned code are unchanged.
