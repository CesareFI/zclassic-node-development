<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fold-profile counter batching

The fold profiler started three parser processes for each of 16 cumulative
profile counters: 48 processes per sample just for those counters. Batch
extraction now uses one awk invocation per profile response, or three per
sample. This reduces the observer cost of identifying sync-stage bottlenecks.

The baseline was the existing Worldstream working copy on
`agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including its earlier stage-parser
improvement. It was not a clean HEAD measurement. The profiler's baseline
SHA-256 was
`56d969333345a9107bb0d556c0ccc09000755cbcd581bb6a425923f785cae456`;
the batched version is
`db21bc977032ea2bd29d5f3a15e007c5eb57dfb74142ad14ef81c933ba818d81`.
Pre-existing changes outside the profiler and its fixture were preserved.

Measured on Linux x86_64, AMD EPYC 7402P, GNU awk 5.2.1, using the real
sampling functions with shell RPC doubles and a fixed timestamp. Each run
produced 20 complete 50-column CSV samples in a private temporary directory.
Ordinary warm filesystem caches and ambient host load apply; no node, peer,
datadir, network, or sleep was involved.

| Measurement | Before | After |
|---|---:|---:|
| External parser processes per sample | 82 | 37 |
| Wall time, 20 samples | 2.99 s | 1.89 s |
| User + system CPU, 20 samples | 5.29 s | 2.84 s |

The Make target repeated the updated benchmark in 1.90 s. Timing is
informational; the deterministic 37-process ceiling is the regression gate.
These numbers measure observer overhead, not an end-to-end IBD speedup.

Reproduce with `make fold-profile-selftest ARGS=--bench`, or
`sh tools/scripts/fold_profile_selftest.sh --bench`. A final script-path
argument selects a saved baseline. Against the baseline, the extended test
passes every output assertion and fails the process ceiling.

The fixture covers both stage schemas, CSV order, absent profiles, negative
and zero counters, integer text wider than floating-point precision, duplicate
keys, multiple lines, and the existing first-integer-match behavior after a
null or string value. It passes with GNU awk and mawk. Mutations selecting the
last match or coercing counters to awk numbers fail. This remains a reader
for the existing compact telemetry shape, not a general JSON parser.

The stopwatch judge and artifact-symmetry selftests pass. Shell syntax,
architecture-tree, shell-host-assumptions, pipefail-status-pipe,
discarded-status, and whitespace checks pass. No C source, generated
interface, validation predicate, consensus rule, optional acceleration,
peer scheduling, or database behavior changes in this slice.

Publication remains unverified: Git metadata is read-only, `origin/main` is
not present locally, and GitHub DNS is unavailable. The full lint attempt
was interrupted during its prerequisite dev rebuild after dependency-download
failures. Focused fixture results do not establish a full publication gate,
live sync performance, or remote SHA.

## Follow-up: batch the eight stage objects

The next measured observer bottleneck was the remaining eight `sed | head`
stage readers. This follow-up replaces those 16 parser processes with one awk
process per response, retaining the previous last-match-on-first-line behavior.
The baseline is the working-copy version identified above by `db21bc97...`,
including the earlier counter batching, not clean HEAD. The new profiler's
SHA-256 is
`377c04105e3af926b5bc473dc22fe1f5722aabb6b0c359ac586d70c66f64e476`.

The same local fixture and host measured:

| Measurement | Before stage batching | After stage batching |
|---|---:|---:|
| External parser processes per sample | 37 | 22 |
| Wall time, 20 samples | 1.92 s | 1.21 s |
| User + system CPU, 20 samples | 2.89 s | 1.71 s |

The Make-target repeat took 1.27 s. The fixture now enforces a 22-process
ceiling; the saved baseline passes all output assertions but fails that ceiling.
Additional cases cover stage duplicates on one line and across lines, malformed
later objects, scalar shadows and leading-zero counters. GNU awk and mawk pass;
a mutation selecting the first same-line stage object fails the new assertion.
These results measure observer overhead only, with no live IBD speed claim.

The artifact-symmetry and stopwatch-judge selftests, POSIX and Bash syntax,
architecture, core seal, shell-host assumptions, discarded-status,
pipefail-status-pipe and `git diff --check` pass. All 554 sealed core files
and 80 section seals match. This follow-up edits only the profiler, its fixture,
and this note; unrelated staged and unstaged work remains intact. No consensus,
validation, acceleration policy, scheduling, database or runtime changes occur.

Publication is still blocked: a fresh branch fetch cannot write the read-only
`.git/FETCH_HEAD`, and the exact-branch remote query fails on GitHub DNS.
The full `make lint` attempt reached its 90-second bound during prerequisite
preparation after the zlib download failed on DNS; it did not complete the
publication gate. Standalone no-API-keys, no-Python and no-warning-suppression
checks passed. No new commit, push, or verified remote SHA is claimed.
