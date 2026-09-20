<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: remove the nested shell from stopwatch quoting

`json_string` in `tools/scripts/stopwatch_json_lib.sh` captured `json_escape`
through command substitution before emitting surrounding quotes. Each field
therefore created an extra shell process, even after the existing pending
change removed external programs from `json_escape`. Cold-start phase profiles,
proof artifacts and recovery evidence call this wrapper repeatedly.

The wrapper now writes the opening quote, calls the existing escaping helper
directly, and writes the closing quote. Escaping behavior and evidence
acceptance are unchanged. The caller's own command substitution remains.

## Measurement

Measured on Linux 6.8.0-139-generic x86_64, AMD EPYC 7402P, Bash 5.2.21,
with warm filesystem caches and ambient load. HEAD was
`c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The baseline includes this checkout's
pre-existing pending library edits; this slice changes only `json_string`.

Each trial captures 500 quotes of a fixed 41-byte string containing quotes,
backslash, newline and tab, with fixture setup excluded from the timing.

| Wrapper | Trial wall seconds | Median seconds | Nested shells per quote |
|---|---|---:|---:|
| Captured escape output | 1.099, 1.090, 1.101 | 1.099 | 1 |
| Direct escape call | 0.555, 0.553, 0.557 | 0.555 | 0 |

Median observer time decreased about 49%. These measurements do not establish
an end-to-end IBD or time-to-tip improvement. No node, datadir or peer was used.

Library SHA-256 identities including the pre-existing edits:

- Baseline: `1cb92175889700a5a8e8f3633921a1dcee3ec6058b899b9b19698767f9f19f2b`
- Changed: `2bf8512397bd18423d67d274cba57c116262987c1bc1ca50f3ca93e4153f5bdc`

## Regression and scope

Run `make stopwatch-quote-selftest ARGS=--bench`, or invoke
`bash tools/scripts/stopwatch_quote_selftest.sh --bench [library]` to compare
another library. The test compares exact output bytes against the original
streaming escaping pipeline, including empty strings, trailing whitespace,
UTF-8 and all non-NUL byte values. It preserves the helper's existing control
byte handling; it does not expand the JSON escaping contract.

A process-identity assertion at the wrapper/helper boundary detects the extra
shell without a host-dependent timing threshold. The baseline passes the byte
checks and fails this assertion. The changed library passes both. A separate
fixture using committed HEAD plus only this wrapper change also passes, so
the improvement does not depend on pending parser/escaping optimizations.

Passing checks: exact-byte/process regression, existing string regression,
artifact-symmetry mutation checks, evidence judge, cold-start, recovery and
triple-run selftests, pipefail status gate and its selftest, discarded-status
gate and its selftest, shell-host-assumption scan, Bash syntax and
`git diff --check`.

Owned changes are this note, the new quote selftest, its Make target and
symmetry prerequisite, and only the `json_string` hunk in the shared library.
Preserve all other staged and unstaged work, including other Makefile and
library hunks. No consensus, cryptography, validation, acceleration policy,
scheduling, database or node-runtime change is part of this slice. No generated
artifacts, raw logs, credentials or production state belong in its commit.

## Publication status

The aggregate Make checks and `make lint` were interrupted after several
minutes with no logged progress beyond template generation; their gates are
incomplete. The focused scripts and shell gates listed above were run directly
and passed. ShellCheck is unavailable; no compiled source changed.

Git fetch cannot write `.git/FETCH_HEAD`
because repository metadata is read-only; remote inspection also fails because
GitHub DNS is unavailable. No commit, push or exact remote-SHA verification
was possible. Complete publication gates and publish only the development
branch when those prerequisites are available.
