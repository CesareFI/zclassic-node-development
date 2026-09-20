<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: batch sync-boundary profile reads

The cold-start stopwatch parsed each reducer-stage-profile response three
times to populate its phase-boundary index. This slice reads those three
counters with one awk process. It preserves the raw snapshot, one RPC per
boundary, index fields, first-line compact-response parsing, and the -1
sentinel for missing/null counters. Cumulative counters remain separated
from last-batch counters. This is external benchmark instrumentation only.

## Baseline and measurement

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The checkout already contained
uncommitted Worldstream work; the baseline was the working script immediately
before this slice, not clean HEAD. Its SHA-256 was
`6c0bde7bec9fb751c39b5b0c173fe3beb783abbb3466711e6a71b050187900ce`.
The resulting script, including selftest registration, has SHA-256
`b3499e8f64e38275a4f465939725943859628f27cb85c08ad614cda08d7a21fe`.

Linux x86_64, AMD EPYC 7402P, Bash 5.2.21. The fixture invokes the real
snapshot writer, uses a local RPC response, and writes temporary snapshots.
No node, chain sync, network load, or production datadir is involved. Tools
and files use ordinary warm filesystem caches; ambient host load is uncontrolled.

| Measurement | Before | After |
|---|---:|---:|
| awk processes per boundary snapshot | 3 | 1 |
| Wall time, 200 snapshots | 5.169 s | 2.968 s |
| User CPU, 200 snapshots | 0.985 s | 0.564 s |
| System CPU, 200 snapshots | 4.984 s | 2.612 s |

These are single-run observer timings, not end-to-end IBD or time-to-tip
improvements. A real run has only its observed phase boundaries; 200 captures
amplify this small cost for measurement. The deterministic process ceiling,
rather than elapsed time, is enforced by the regression.

## Reproduction and validation

```sh
bash tools/scripts/stopwatch_phase_profile_selftest.sh --bench
bash tools/scripts/cold_start_to_tip_stopwatch.sh --selftest
```

The focused script accepts an optional final path to an older stopwatch.
The baseline passes output checks and fails the one-parser ceiling with three
parsers. Coverage includes exact raw snapshots and index values, zero,
missing/null fields, absent domains, missing process/RPC observations,
multi-line and 128 KiB responses, and appending consecutive boundary rows.
Removing the last-batch scope fence makes the null-counter fixture fail.

The full stopwatch selftest passes. Bash syntax, architecture-tree,
shell-host-assumption, pipefail-status-pipe, and `git diff --check` pass.
`make lint-fast ZCL_LINT_SERIAL=1` did not complete within a 50-second bound;
output showed prerequisite template generation and missing Tor archives.
It is not recorded as passing. No compiled source changes in this slice.

Only the stopwatch, its new focused selftest, and this report belong to this
slice. Existing dirty work is preserved. Consensus and validation semantics,
optional acceleration, legacy peer/request scheduling, database behavior,
and node runtime are unchanged. Test outputs remain in temporary directories;
no secrets, binaries, logs, or datadirs belong to the proposed change.

Publication is incomplete: fetch and staging fail because `.git` is mounted
read-only; `git ls-remote origin refs/heads/agent/worldstream-ibd-20260918`
also fails because GitHub DNS is unavailable. No commit or push occurred,
and remote SHA equality is unverified.
