<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reduce tip-agreement observer parsing cost

This slice changes only the tip-agreement judge's field extraction, its
regression/benchmark script, and one recipe line in `make
tip-agreement-selftest`. The judge already matched each field, then constructed
another regular expression to strip its key. String fields also used a third
match to strip the closing quote. Directly slicing the existing match avoids
those redundant substitutions. Matching rules, missing-field behavior, first
match selection, splice detection, verdicts and acceptance thresholds remain
unchanged.

Baseline: `tools/scripts/tip_agreement_judge.sh` at
`c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. This file was clean at entry. Its SHA-256 is
`b8ad3f5a346c59c26af2ca80e897fc7e210124c77f312b4053f4dbea77231031`.
The changed judge SHA-256 is
`38ed644d659fdcafaeb0b5459c97bfa2c2f0a8ef889e2ac5c002aa5237d654be`.
All pre-existing staged and unstaged work was preserved; the Makefile already
contained unrelated changes, and this slice adds only the parser selftest
invocation to its existing tip-agreement target.

Measured on Linux x86_64, AMD EPYC 7402P, GNU awk 5.2.1, ordinary warm filesystem
caches and ambient host load. Each invocation launches the actual Bash judge,
reads a synthetic flat JSONL ledger, and produces its verdict. No nodes, RPCs,
network traffic, production ledgers or datadirs participate.

| Fixture | Baseline wall, three runs | Changed wall, three runs |
|---|---|---|
| 52,560 retained rows, one year at the shipped 600-second cadence | 0.214 / 0.213 / 0.220 s | 0.192 / 0.190 / 0.191 s |
| 86,401 in-window rows, synthetic one-second cadence | 12.577 / 12.626 / 12.603 s | 7.104 / 7.117 / 7.053 s |

Median evaluation time fell about 11% and 44%, respectively. The second
fixture stresses reading every field; it is not the shipped recorder cadence.
Complete verdict output matches the baseline for every benchmark pair.
These measurements establish observer overhead only, not faster end-to-end
IBD or live time-to-tip. Timing is informational, never a test threshold.

Reproduce from the repository root:

```sh
baseline=$(mktemp /tmp/zcl-tip-parser-baseline.XXXXXX)
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/tip_agreement_judge.sh > "$baseline"
bash tools/scripts/tip_agreement_parser_selftest.sh --bench "$baseline"
rm -f "$baseline"
make tip-agreement-selftest
bash tools/scripts/tip_agreement_judge.sh --selftest
```

The regression extracts the actual readers and makes 452 byte-string
comparisons with the original substitution readers and explicit expected
values. It covers all six keys, missing and empty values, signed and
zero-prefixed numbers, quoted values, repeated fields, whitespace and trailing
text. An intentionally incorrect string offset fails the regression. Both
GNU awk and mawk pass the parser and judge selftests. The complete registered
tip-agreement Make target also passes, including recorder and observer cases.
An isolated copy with unchanged HEAD helpers and test harness also passes,
showing the slice does not depend on the pre-existing dirty script changes.

Consensus core sealing, architecture, Bash syntax, shell-host assumptions,
discarded-status, pipefail-status-pipe, no-Python, no-API-keys,
no-warning-suppression, POSIX ERE and whitespace checks pass. No consensus predicates,
cryptography, optional acceleration policy, node runtime, peer scheduling or
database code changes in this slice. Core seal verification reports all 554
files and 80 sections matching. The change contains source and documentation
only; benchmark fixtures and outputs stay in temporary directories.

Publication is unavailable in this environment: fetching fails because Git
metadata is read-only, and querying the exact development branch fails because
GitHub DNS is unavailable. Full lint encountered the unavailable zlib download
during prerequisite preparation and was interrupted without completing.
Focused checks do not establish the
full publication gate. No commit, push or verified remote SHA is claimed.
