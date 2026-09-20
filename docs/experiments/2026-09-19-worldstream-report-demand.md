<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: avoid page diagnostics without observed explorer readiness

Owned surface: the final report in `tools/bench_fresh_sync.c`, its isolated
regression and the existing `bench-fresh-sync-selftest` target. No node runtime,
peer scheduling, database, consensus or validation code changes.

Baseline checkout: `agent/worldstream-ibd-20260918` at
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with extensive pre-existing staged,
unstaged and untracked Worldstream work. The baseline for this slice is the
working source at entry, not that commit alone. Preserve that earlier work.
Baseline benchmark source SHA-256:
`c4bc524d1b1608ac7fd2038b8da77cea5a75c7f95ccb637e3866362a1a4436e3`.
Updated benchmark source SHA-256:
`7f54895e99a7dad9b94e7affa1cac1147f867f3688d99b966c4a0565b9829104`.

## Witness and result

The benchmark fetched all four diagnostic explorer pages after an incomplete
run even when explorer readiness had never been observed. The production
report, compiled into an isolated C23 fixture, made four requests in this
case. Each production request uses curl's two-second maximum transfer time:
eight seconds of possible additional HTTP waiting after the measurement ends.

Guard the page diagnostics with the existing observed-readiness timestamp.
Without it, emit an explicit not-probed report. Always retain the independent
`validationstatus` observation and the existing benchmark success/failure
return. A prior readiness observation still enables all four page diagnostics,
even if the benchmark subsequently fails its completion criterion.

| Report scenario | Before page requests | After page requests |
| --- | ---: | ---: |
| No readiness observed; incomplete | 4 | 0 |
| Readiness observed; incomplete | 4 | 4 |
| Readiness observed; complete | 4 | 4 |

Each case runs with both a successful and a failed validation-status RPC.
The request counts are measured fixture results. Eight seconds is a bound
from the four HTTP timeouts, not measured time-to-tip improvement. No live IBD,
network or production datadir participates in this qualification.

## Reproduction and validation

```sh
bash tools/scripts/bench_fresh_sync_report_demand_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_page_size_selftest.sh --analyze
```

The new test accepts `--baseline` and an optional source path. Against the
saved pre-change source, baseline measurement passes and the new zero-request
requirement fails. With the change, all six report cases pass. All 24 outcome
cases and the page-size observer regression pass. These three fixtures compile
with C23, `-Wall -Wextra -Werror` and GCC 14.2 `-fanalyzer`; the new fixture
also uses `-pedantic`. Bash syntax and `git diff --check` pass.

Running the existing aggregate's shell recipes directly passes 15 of 16
scripts, including the new regression. The timing script fails with
`t_done == 21` expected and `19` observed. It produces identical output against
the saved pre-change source. Its polling loop is unchanged by this slice;
no expectation was relaxed.

The standalone benchmark links using the Makefile's compiler recipe. Full-file
strict analysis fails on pre-existing certificate-copy command truncation
warnings, reproduced against the saved source. Normal `make bench_fresh_sync`
cannot prepare missing Tor submodules because `.git/config` is read-only.
The three attempted Make invocations (build, aggregate test, `lint-fast`)
were interrupted after making no further visible progress; none is claimed
green. The aggregate's actual test scripts were run directly as described
above. No lint threshold or build prerequisite was weakened.

## Publication boundary

The branch remains unchanged. `git fetch origin main` fails because
`.git/FETCH_HEAD` is read-only; the environment also denies Git metadata writes
needed to stage and commit. `git ls-remote origin` fails resolving GitHub.
No commit or push was made and no fresh remote SHA verification is claimed.
The existing cached remote-tracking SHA equals the starting local SHA only.
This slice remains local pending normal integration gates and publication on
the designated development branch. No generated output, credentials, logs,
datadirs or binaries belong in its eventual commit.
