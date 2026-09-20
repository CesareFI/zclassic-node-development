<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: compact integer observation cost

The shared `evidence_json_int` reader started one `sed` process for every
integer observation. Its consumers include sync tip-agreement height/peer
observations and the node SLO blocker's active count. Compact string and boolean
readers already avoided that process. This slice removes the remaining parser
process for identifier keys in single-line responses of at most 4096 characters.
Large/multiline responses and legacy regular-expression keys retain `sed`.

Integer text is preserved without arithmetic conversion, including leading
zeros and counters wider than 64 bits. Duplicate-key, first-matching-line,
missing-value and existing integer-prefix behavior are unchanged. This is an
observer optimization, not a change to JSON acceptance or consensus validation.

## Measurement

Base commit: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`, with pre-existing uncommitted Worldstream work.
The baseline was the actual pre-edit library, not the older committed version.
Its SHA-256 was
`741ff8c5587c3fd14c43571220143044b44aa995f826986d2e9a4105708fc87d`;
the resulting library's SHA-256 is
`686e23df8fd254c617f0af0fe157b6d20d3a0c88a4aa63f00d2a233a9e955288`.

Host: AMD EPYC 7402P, 48 logical CPUs, Linux 6.8.0-139-generic x86_64,
Bash 5.2.21, `LC_ALL=C`. Local in-memory fixture, warm host caches, no node,
datadir or network. Each run reads height, stage and readiness 500 times from
`{"height":3200000,"stage":"header_admit","ready":false}`. Direct function
calls are timed; caller command-substitution overhead is not included.

| Observation | Before | After |
| --- | ---: | ---: |
| External parsers per three-field observation | 1 | 0 |
| Wall seconds, run 1 | 1.334 | 0.114 |
| Wall seconds, run 2 | 1.532 | 0.108 |
| Wall seconds, run 3 | 1.328 | 0.113 |
| Median wall seconds | 1.334 | 0.113 |

The median observer reduction is about 92%. This does **not** establish an
end-to-end IBD or time-to-tip improvement. Larger responses use the original
reader and are not claimed to be faster.

## Reproduction and scope

Run `bash tools/scripts/evidence_json_readers_selftest.sh --bench`.
Its optional second argument selects an alternate library for comparison.
The strengthened process-budget assertion fails on the baseline and passes
on the new reader. The existing `make evidence-selftest` registration already
includes this test; no test-registration changes are needed.

Focused coverage includes negative/zero/wide integers, leading zeros,
duplicates, malformed and absent values, integer prefixes, line boundaries,
4096/4097-character dispatch, regex-key fallback and large responses.
Adjacent string/boolean, escaping, peer-count, service-property, RSS and
directory-size fixtures passed, as did the end-to-end tip-agreement fixtures.
All remaining `evidence-selftest` constituents (intervention ledger,
intervention declaration and public explorer) also passed directly.
Bash syntax, pipefail-status, discarded-status, shell-host-assumptions,
no-API-keys, no-Python, POSIX-regex and `git diff --check` checks passed.
`make evidence-selftest` and `make lint` were attempted, but remained in setup
without reaching their recipes and were interrupted. Full Make/lint completion
is not claimed. No C code changed, so there is no compiler result for this slice.

Only the observer library, its existing regression and this record belong to
this slice. Existing dirty work is preserved. No consensus, custody, runtime,
scheduling, database, acceleration default or validation path changes; no
production state, secrets, binaries or benchmark output belong in the slice.

Publication is blocked in this environment: `.git` is read-only, so the
required fetch fails, and origin lookup fails resolving `github.com`.
There is no new commit, push or verified remote SHA for this slice.
