<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream readiness observer cost

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`,
`tools/scripts/lane_health.sh`, Linux x86_64, AMD EPYC 7402P,
Bash 5.2.21. The lane observer reads four readiness booleans from the same
status response. Each extraction launched `grep` and `head`: eight external
parser processes per lane, or 24 for the three-lane summary. This slice
replaces that pipeline with Bash's regular-expression match, preserving the
first boolean match on the first matching line and `null` on no match.

The hermetic benchmark performs 250 repetitions of those four readings from
a fixed status fixture. It includes command-substitution subshells, ordinary
warm filesystem caches and ambient load. It performs no RPCs or node work.

| 1,000 readings | Before | After |
|---|---:|---:|
| Wall time | 5.471 s | 1.504 s |
| User + system CPU | 8.624 s | 1.603 s |
| External parser processes | 2,000 | 0 |

These numbers describe observer overhead, not end-to-end IBD or time to tip.
Elapsed time is informational; the regression gates on returned values and
absence of external parser calls. Reproduce with:

```sh
bash tools/scripts/lane_health_bool_selftest.sh --bench
ZCL_LANE_HEALTH_SELFTEST=1 bash tools/scripts/lane_health.sh
```

The benchmark accepts an optional final path to a baseline script. The old
reader passes all 20 value cases and fails the process budget. Cases cover
missing/unknown values, duplicate keys, whitespace, multiline responses and
256 KiB responses. A greedy last-match mutation fails the duplicate-key case.
The integrated selftest also passes with all shared libraries taken directly
from baseline HEAD, independently of pre-existing checkout changes.

The tip-agreement and soak fixture suites, shell syntax, whitespace, core seal,
and scoped lint gates pass (architecture, shell host assumptions, POSIX ERE,
no Python, no API keys, and no warning suppression). A public-node build was
attempted but failed to fetch missing dependency archives because GitHub DNS
was unavailable; full build-dependent integration evidence is unavailable.
No C or generated source changes are part of this slice. Consensus, validation,
optional acceleration, peer scheduling and database behavior are unchanged.

Requalification on 2026-09-18 measured 5.297 s before and 1.543 s after for
the same 1,000 readings (user + system: 8.299 s and 1.643 s). The baseline
again passed all value cases and failed the external-process budget; the
candidate passed with shared libraries from baseline HEAD. The regression
now also denies PATH lookup for true, false and absent values, so invoking
a parser through `command` cannot bypass the tool wrappers. The last-match
mutation is rejected. The reader retains the original function length,
keeping the flag catalog's source-line references valid without changing it.

The tip-agreement and soak-evidence targets, core seal, shell syntax and
`git diff --check` passed again. `make lint-fast` remains red on unrelated
existing changes (fresh-sync complexity and other flag pointers) and host
constraints (the `.agents`/`.codex` root entries and Windows-check scratch
access). `make z23` cannot download missing dependencies because GitHub DNS
does not resolve. No full node build or end-to-end IBD claim is made.

The earlier publication attempt could not write Git metadata. On the next
qualification run, fetching `origin/agent/worldstream-ibd-20260918` and staging
the two scripts succeeded; the branch still matched baseline HEAD. There is
no `main` ref on this origin. Other staged and unstaged slices remain separate.
The readiness slice consists only of this note, `tools/scripts/lane_health.sh`,
and `tools/scripts/lane_health_bool_selftest.sh`.

Final requalification measured 5.322 s before and 1.498 s after for 1,000
readings (user + system: 8.365 s and 1.599 s). Baseline passed the 20 value
cases and failed the process budget; the candidate passed both. The integrated
test passed in an isolated baseline-source tree with only the two candidate
scripts overlaid. A greedy last-match mutation failed `first_true`. These
checks do not depend on the other uncommitted Worldstream improvements.

Architecture and shell-host checks passed. The core seal again verified all
554 files and 80 sections. The checkout's `make lint-fast` failed on unrelated
fresh-sync complexity, stale flag references, extra root entries, and an
unwritable Windows-check scratch directory. A public binary build failed to
download missing OpenSSL dependencies because GitHub DNS did not resolve.
These limitations leave full build-dependent integration unqualified; the
shell-only measurements above do not establish live time-to-tip acceptance.

The final `make lint` attempt reached its 45-second bound during prerequisite
preparation after a zlib download failed on DNS. A subsequent branch fetch
failed to write `.git/FETCH_HEAD`, and the three-path `git commit --only`
failed to create `.git/index.lock` because the filesystem was read-only.
Thus this run produced no commit or push and has no verified remote SHA.
The focused shell checks pass, but publication and full integration remain
incomplete; the next run should finish this slice before starting another.
