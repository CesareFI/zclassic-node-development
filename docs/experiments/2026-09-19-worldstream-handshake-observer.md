<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream peer-handshake observation cost

Base commit: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. Linux x86_64, Bash 5.2.21. This checkout
already contained substantial staged and unstaged work, which is preserved.
The measured `pl_handshake_unix` function was unchanged from the base commit.
No node, network peer, wallet or production datadir participates in this test.

The cold-start stopwatch's peer-connect phase repeatedly parses peer lifecycle
telemetry until it observes a usable handshake. Each observation previously
started `tr` to split peer objects and `awk` to select the earliest positive
handshake with an advertised height. One awk invocation now splits each input
line into the same brace-delimited records and performs that selection.
Timestamp selection, peer boundaries, newline boundaries, missing-value
sentinels and the optional height requirement are unchanged.

Three runs of 500 observations, using a three-peer compact fixture and warm
tool/filesystem caches on this host:

| Measurement | Before | After |
|---|---:|---:|
| External tools per observation | 2 | 1 |
| Wall time, run 1 | 2.392 s | 1.905 s |
| Wall time, run 2 | 2.359 s | 1.903 s |
| Wall time, run 3 | 2.308 s | 1.870 s |
| Median wall time | 2.359 s | 1.903 s |

The median observer cost is about 19% lower. This is a local microbenchmark,
not measured end-to-end IBD or time-to-tip acceleration. Timing varies with
host load; the regression gates behavior and external-tool count, never elapsed
time. Observation stops once this phase boundary has been recorded, so savings
depend on how many unsuccessful handshake observations a real run makes.

Reproduce:

```bash
bash tools/scripts/stopwatch_handshake_selftest.sh --bench
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/cold_start_to_tip_stopwatch.sh > /tmp/handshake-baseline.sh
bash tools/scripts/stopwatch_handshake_selftest.sh --bench /tmp/handshake-baseline.sh
```

The baseline passes value checks and intentionally fails the one-tool budget.
The test extracts only the production reader, without executing harness setup.
It covers earliest selection, the height requirement, missing/negative/zero
values, distinct and nested peer records, multiline input, duplicate fields,
whitespace, leading zeroes and inputs exceeding a pipe buffer. A mutation that
selects the latest rather than earliest peer fails the regression. The main
stopwatch selftest invokes this test.

Validation passed: focused regression/benchmark, complete cold-start stopwatch
selftest, artifact symmetry selftest, triple-run selftest, Bash syntax,
pipefail-status and discarded-status checks, shell-host-assumption check,
their checker selftests, the standalone architecture-tree checker, and
`git diff --check`. ShellCheck is unavailable. The `make lint-fast` and
`make check-architecture-tree` invocations did not complete during this attempt
and were interrupted; the architecture checker was then run directly.
The flag-registry checker reports 17 pre-existing stale pointers in other
modified files after refreshing the four references for this script. No full
node build, live synchronization, or complete lint pass is claimed.

This slice changes benchmark parsing and source-location metadata only.
Consensus, cryptographic validation, optional acceleration behavior, legacy
peer scheduling, block-request scheduling, databases and node runtime are
unchanged. All temporary output stays outside the tracked tree. Publication
is blocked: `.git` is read-only and the origin lookup fails DNS resolution.
There is no new commit, push or verified remote SHA for this slice.
