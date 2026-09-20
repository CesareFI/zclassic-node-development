<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stop revisiting completed drive-profile columns

The external fold-profile observer's `jnums` reader continued visiting every
requested output column on later response lines even after all columns had
values. Count newly populated columns and skip that loop after completion.
Continue draining the input to EOF: an early process exit can break the
producer under pipefail. Last integer match on the first matching line,
stage triples, repeated requested keys, absent-value sentinels, and wide
integer text remain unchanged.

This slice changes instrumentation only. Consensus, mandatory validation,
optional acceleration, node scheduling, database behavior, and production
state are unchanged. No node was launched.

## Measurement

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The baseline is the existing
working script, including earlier uncommitted work. Its SHA-256 is
`10f0bbb1c75c8f78de1204ee8ad8e6049a4a02782bd6694955a6f06992f8f882`;
the resulting script's SHA-256 is
`9d9d73af130c0ce92c9d338f48e90df667e47eb74b82d55d043745f5f42bc2ff`.

Linux x86_64, GNU Awk 5.2.1, dash; warm tool/filesystem caches and uncontrolled
ambient load. Each benchmark runs 500 real reader calls with the same
17,083-byte synthetic input: two scalar counters and one stage triple on
the first line, followed by 1,000 diagnostic lines. There is no RPC, peer,
network or datadir. This is a multiline stress fixture, not a captured node
response or an end-to-end IBD benchmark.

| Measurement | Before | After |
|---|---:|---:|
| Column-loop visits per read | 3,003 | 3 |
| Wall seconds, three runs | 2.78 / 2.77 / 2.80 | 2.55 / 2.50 / 2.55 |
| Median wall seconds | 2.78 | 2.55 |
| User CPU seconds, three runs | 1.15 / 1.14 / 1.16 | 0.89 / 0.87 / 0.90 |

The median fixture improvement is about 8%. Compact single-line responses
do not benefit from skipping later lines; missing requested columns still
require scanning all input. Five parser processes remain per complete
sample. No time-to-tip improvement is established.

## Regression and validation

```sh
sh tools/scripts/fold_profile_scan_selftest.sh --bench
sh tools/scripts/fold_profile_selftest.sh
sh tools/scripts/fold_profile_rpc_selftest.sh
sh tools/scripts/fold_profile_drive_selftest.sh
```

All four pass directly. The scan test also accepts a final path to the
baseline script: its values pass but the new work ceiling fails at 3,003
visits. The extension checks duplicate/missing/multiline values, repeated
requested keys, wide counters, empty selections, and draining a response
larger than 1 MiB under pipefail. Mutating the completion increment to two
is rejected by the value tests; replacing the drain with early exit is
rejected with a broken pipe. Timings use the uninstrumented function.

POSIX/Bash syntax checks, the pipefail status-pipeline gate and its selftest,
and `git diff --check` pass. No compiled source changed. The combined
`make fold-profile-selftest lint-fast` invocation timed out after 50 seconds
during initialization, before either target completed; these Make gates
remain unverified. Generated templates were reported unchanged.

Owned delta: the `jnums` completion guard, the appended drive-reader section
of `fold_profile_scan_selftest.sh`, and this report. The pre-existing script
and test changes are preserved and must not be folded into this slice.
Baseline copies, raw timing output, and mutation fixtures are under
`/tmp/worldstream-drive-scan`, outside the tracked source tree.

Publication is incomplete. Fetch failed because `.git/FETCH_HEAD` is
read-only; the read-only remote query failed because GitHub DNS resolution
is unavailable. No commit or push was made, and remote SHA equality is
unverified. The branch and HEAD remain unchanged.
