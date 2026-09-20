<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: consolidate public explorer observation

Scope: external explorer responsiveness/readiness instrumentation during sync.
The HODL smoke check read each API response with five separate grep processes
and two sed processes, plus two head processes for the numeric fields. One
awk process now collects the same observations in a single pass. It keeps
reading after finding readiness so a late wait/retry marker still fails.

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`; the smoke script was
clean at the start of this slice. The checkout already contained unrelated
Worldstream changes. Both measurements held its modified shared evidence
library constant. Host: Linux x86_64, AMD EPYC 7402P, Bash 5.2.21, GNU awk
5.2.1, ordinary warm filesystem caches and ambient host load.

The fixture uses the real recorder with injected fetches, isolated temporary
ledgers, and no network or running node. Each of 20 benchmark observations
reads a 557,229-byte API response, with readiness at the front and a wait
marker at the end. Timings include the complete recorder and process-count
wrappers; they are informational rather than acceptance thresholds.

| Measurement | Before | After |
|---|---:|---:|
| API-file reader processes per observation | 7 | 1 |
| Wall time, 20 observations | 2.558 s | 2.041 s |
| User CPU | 0.579 s | 0.519 s |
| System CPU | 2.269 s | 1.704 s |

This is roughly 20% less observer wall time in this fixture, not a measured
change in node throughput, GUI latency, or end-to-end IBD/time-to-tip.

Reproduce with:

```bash
bash tools/scripts/public_explorer_observer_selftest.sh --bench
bash tools/scripts/public_explorer_smoke.sh --selftest
```

The observer selftest accepts an optional final path to an older smoke script
with its sibling `lib/evidence_sources.sh`. The baseline passes evidence
assertions and fails the one-reader budget. Regression coverage includes 20
cases for readiness flags, failure ordering, every wait phrase, late markers,
HTML degradation, missing fields, compact-format expectations, duplicate
fields, multiline responses, and exact wide-integer text. An additional
injected reader failure verifies that plausible partial output is discarded
and a failed observation is still recorded. The existing smoke selftest
continues to cover outage recording, rotation, recovery, and per-base streaks.
The new selftest runs through that existing `evidence-selftest` entry point.

Validation: focused tests pass under GNU awk and mawk. Every script in the
Makefile evidence-selftest recipe passes when invoked directly. Bash syntax,
architecture, shell-host-assumption, status-pipeline and whitespace checks
pass. The complete smoke selftest also passes in an isolated directory using
the committed evidence library, without the checkout's earlier library edits.
The Make aggregate evidence and lint targets were interrupted during
prerequisite processing; the direct evidence run supplies fixture evidence,
not a successful Make/build claim. No C source or generated interface changes
are required for this shell-only slice.

Running the exact 32 `LINT_FAST_GATES` through the existing lint driver finishes
with 28 passes and four unrelated checkout/environment failures: `.agents`
and `.codex` root entries, pre-existing fresh-sync benchmark complexity,
37 stale flag-catalog source-line pointers, and an unwritable Windows-check
scratch directory. None of those failing source paths belongs to this slice.
Full integration lint is therefore not green.

Only the smoke observer, its new fixture test, and this report belong to this
slice. No consensus, cryptography, validation, optional acceleration, peer
scheduling, database, custody, deployment, or production state is changed.
Temporary fixture output is kept outside the source tree. Existing dirty
work remains separate.

Publication is blocked: Git metadata is read-only (`git fetch origin main`
cannot open `.git/FETCH_HEAD`), and `git ls-remote origin` cannot resolve
GitHub. The branch remains `agent/worldstream-ibd-20260918`; no commit, push,
or verified remote SHA is claimed.
