<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reduce counter-parser diagnostic-prefix work

This slice changes only the fold-profile observer, its local fixtures and Make
test registration. It changes no consensus, node validation, peer scheduling,
database, custody or optional acceleration behavior. It measures observer cost,
not end-to-end IBD or time to tip.

## Baseline and bottleneck

Branch: `agent/worldstream-ibd-20260918`. HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The checkout already contained
substantial unrelated staged and unstaged work. The exact working-file baseline
of `tools/scripts/fold_profile.sh` has Git blob identity
`a75a291649349eefb5eb83b167ef0dfc1ac57b04`; HEAD alone does not reproduce it.
The entry file is retained locally at
`/tmp/worldstream-profile-prefix-slice/before.sh` for comparison.

`jnums1` located a literal telemetry key, then applied its numeric-field regex
to the entire response line. A 50,000-field diagnostic prefix caused three
regex calls to inspect 3,683,691 bytes, despite requiring only two distinct
counter values. The new deterministic regression fails on that baseline.

The reader now uses the literal position, checks the same comma/line boundary,
and applies an anchored regex to a small window. The window expands if an
integer reaches its edge, preserving even unusually wide integer text without
copying ordinary diagnostic tails. Missing counters, first valid occurrences,
malformed fields, exact wide integers and multiline draining retain their
existing behavior. Existing scan instrumentation follows the new expression;
its acceptance thresholds are unchanged.

## Measurement

Linux 6.8.0-139-generic, x86_64 AMD EPYC 7402P, GNU Awk 5.2.1. Local synthetic
responses are loaded into shell memory before repeated reads; no node, network
or datadir participates. CPU affinity and ambient host load are uncontrolled.
These are individual wall-time observations, not statistical SLO evidence.

| Fixture | Reads | Baseline seconds | Candidate seconds |
|---|---:|---:|---:|
| No diagnostic prefix | 100 | 0.44 | 0.43 |
| 500 diagnostic fields before counters | 100 | 0.56 | 0.46 |
| 50,000 diagnostic fields before counters | 100 | 12.13 | 2.61 |
| Sparse profile with large prefix | 30 | 2.23 | 1.28 |
| Complete profile with large diagnostic tail | 30 | 0.60 | 0.58 |

The new fixture observes 204 regex-input bytes at every prefix size, against a
1,024-byte deterministic budget. Literal lookup and input draining still scale
with response size; this does not claim constant-time parsing.

Reproduce without a node:

```sh
sh tools/scripts/fold_profile_counter_prefix_selftest.sh --bench
sh tools/scripts/fold_profile_missing_keys_selftest.sh --bench
```

Pass `--baseline --bench /path/to/before.sh` to the first test to measure the
baseline without enforcing the new work budget. Normal mode fails against the
baseline. `make fold-profile-counter-prefix-selftest` is registered, and the
existing `fold-profile-selftest` aggregate depends on it.

## Validation and publication limits

All 11 `fold_profile_*selftest.sh` scripts pass. The new regression passes with
GNU awk, mawk and BusyBox awk, including window boundaries, negative values
and 1,000-digit integers. A separate deterministic 300-row malformed/duplicate
corpus matched baseline output. Shell syntax checks, discarded-status and
pipefail gate self-tests/scans, architecture-tree and the consensus-core seal
check pass. The seal verified 554 files and 80 sections. `git diff --check`
passes. No compiled source changed; compiler validation is not applicable.

The combined Make check attempt timed out after 60 seconds in prerequisite
work before reaching its gates; a 30-second `make lint` attempt likewise timed
out. Direct checks above completed, but full lint and Make target execution
remain unverified. The checkout lacks the public node binary and Tor archives.

The slice contains no credentials, datadirs, logs, binaries or benchmark output.
Earlier edits are preserved. Publication is blocked: `.git` is read-only,
fetch cannot write `FETCH_HEAD`, `origin/main` is unavailable locally, and the
remote branch lookup fails because GitHub DNS cannot resolve. No commit or push
was made, and no remote SHA verification is claimed.
