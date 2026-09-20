<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream stopwatch ledger reader cost

The shared stopwatch alarm reader launched `grep`, `head` and `sed` for
every string field, including every verdict in a full-history scan. The
existing early-failure optimization avoided later classification but still
paid this parsing cost for every subsequent row. Bash matching now reads
these compact string fields and checks field presence without external
parser programs. Shell command-substitution processes still exist.

The baseline is the existing staged Worldstream working copy on
`agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including its prior uncommitted
classification optimization. This is not a clean-HEAD comparison. Baseline
library SHA-256:
`5bf8faa9894286fe5bc4c9c444623a73d0f84a771566adeab5f5763b5daf7dd7`.
Changed library SHA-256:
`b84f8e3b082125943bbbd5914c05abe04c7843afd94032f25f19a3eb180f3a14`.
Earlier staged and unstaged work is preserved.

Measured on Linux x86_64, AMD EPYC 7402P, Bash 5.2.21. The synthetic ledger
contains one failure followed by 1,000 benign skips. Three scans use warm
filesystem caches and ambient host load; lint preparation was also active.
There is no node, datadir, network or live ledger in this benchmark.

| Measurement | Before | After |
|---|---:|---:|
| Wall seconds, three scans | 4.767 / 4.807 / 4.813 | 1.196 / 1.219 / 1.354 |
| Median wall seconds | 4.807 | 1.219 |
| External parser programs per verdict | 3 | 0 |

This is approximately 75% less observer wall time on this fixture. It does
not establish faster IBD or time to tip. Elapsed time is informational;
the deterministic regression requires parsing with no tools on PATH.

Reproduce the current reader with:

```sh
bash tools/scripts/stopwatch_skip_parser_selftest.sh --bench
bash tools/scripts/stopwatch_skip_class.sh --selftest
```

The benchmark accepts a saved baseline library as its final argument. The
baseline passes all 20 field cases and fails the no-external-parser gate.
Cases cover first duplicate selection, missing/empty/null/numeric fields,
similar keys, compact formatting, multiline boundaries and literal escape
handling. This remains the existing flat ledger reader, not a general JSON
decoder. Alarm classes, thresholds, full-history coverage and verdicts are
unchanged. Removing the presence-check pipeline also removes its obsolete
entry from the shrink-only pipefail baseline.

The shared classifier, stopwatch judge, cold-start stopwatch, triple-run
driver and artifact-symmetry selftests pass. Bash syntax, architecture,
discarded-status and pipefail checks pass. The core seal verifies all 554
files and 80 sections unchanged. The slice touches no consensus, validation,
optional-acceleration policy, peer scheduling, database or runtime code.
Only source, regression and documentation files belong to this slice.

Publication is blocked. Git metadata is read-only, `origin/main` is absent
locally, and querying origin fails because GitHub DNS is unavailable.
`make lint-fast` ran all 32 gates: 28 passed, four failed on existing root
entries (`.agents`, `.codex`), the existing fresh-sync benchmark complexity
increase, stale flag-registry pointers, and a restricted Windows-test scratch
directory. No gate was weakened or unrelated work changed to clear these.
No commit, push or verified remote SHA is claimed.
