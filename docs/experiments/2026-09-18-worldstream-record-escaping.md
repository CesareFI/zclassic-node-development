<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream recovery stopwatch ledger formatting

Owned surface: `tools/scripts/netdisrupt_stopwatch_run_and_record.sh` JSON
string emission. Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`.
The checkout contains other uncommitted Worldstream work; none is part of this
slice. The formatter and its new regression also pass in an isolated tree
with the surrounding stopwatch scripts taken from that exact baseline.

## Measured bottleneck

The collector escapes seven strings for every recovery benchmark ledger row.
Each string used a `printf | sed | tr` pipeline inside command substitution:
14 external parser program launches per row, in addition to shell processes.
Bash substitutions now preserve the same backslash, quote, tab, CR and
newline-to-space behavior without those external launches. Ledger schema,
verdict mapping, budget, locking and alarms are unchanged.

Environment: Linux 6.8.0-139-generic x86_64, AMD EPYC 7402P (24 cores,
48 logical CPUs), Bash 5.2.21, `LC_ALL=C`. Three sequential trials per variant,
100 batches of the seven representative ledger strings per trial. The input
is in memory; these are warm shell/tool runs without cache eviction or an
exclusive-host reservation. No network or chain data is used in the benchmark.

| Formatter | Trial wall seconds | Median |
|---|---|---|
| Baseline | 2.771, 2.741, 2.777 | 2.771 s |
| Builtin substitutions | 0.772, 0.777, 0.787 | 0.777 s |

This is a 72% reduction in this string-emission workload, approximately
19.94 ms saved per seven-string batch. It is **not** evidence of reduced
IBD time or time to tip: collection happens after the measured recovery run.
It reduces observer CPU/process overhead when recording synchronization
benchmarks. The remaining seven `json_string` command substitutions still
create shells; this change claims only removal of the external parser programs.

## Reproduction and validation

```bash
bash tools/scripts/netdisrupt_record_escape_selftest.sh --bench
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/netdisrupt_stopwatch_run_and_record.sh > /tmp/netdisrupt-record-before.sh
bash tools/scripts/netdisrupt_record_escape_selftest.sh --bench /tmp/netdisrupt-record-before.sh
```

The baseline prints its timings, then intentionally fails the no-external-parser
regression. Timings are observations, never acceptance thresholds.

The regression compares exact bytes against the legacy formatter for 13 cases,
including empty input, literal escapes, mixed controls, shell metacharacters,
Unicode, trailing newlines and a string over 32 KiB. It also runs the actual
collector against a mock stopwatch for all seven verdict classes and compares
the complete ledger row. Fixtures use only temporary directories; the optional
classifier's missing-library fallback is exercised, with no node invocation,
process signalling, operator ledger or syslog alarm.

Passing checks: formatter regression, isolated seven-verdict collector test,
recovery stopwatch selftest, evidence-judge selftest, Bash syntax, repository
discarded-status and pipefail-status-pipe checks, and `git diff --check`.
The stopwatch and judge selftests also pass using their committed baseline
sources, independently of existing dirty changes. ShellCheck is unavailable.
Full `make lint` was stopped after encountering missing vendor dependencies
and GitHub DNS failure while fetching zlib; full lint is not claimed green.

Only shell benchmark tooling, its regression and this note change. No consensus,
cryptography, chain state, peer scheduling, database behavior or optional
acceleration policy changes. Independent Zclassic validation is untouched.
