<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reduce duplicate-field copying in the fold observer

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold profiler's `jnums` reader preserves the last valid duplicate on the
first matching line. Its next-key search copied the entire remaining line
after every occurrence. Dense repeated fields therefore caused quadratic
temporary copying. A synthetic response with 10,000 repeated counters copied
699,625,510 bytes per read just for these searches.

The search now checks a nearby window first, falling back to the remaining
suffix only when necessary. The two windows overlap by the key length so a
key crossing the boundary remains visible. Selection, malformed-field handling,
missing-value zeros, exact integer text, stage triples and CSV order are
unchanged. This does not make arbitrary telemetry parsing constant-cost or
establish an end-to-end IBD improvement.

## Owned change and reproduction

This slice owns the seven-line expansion of the duplicate search in
`tools/scripts/fold_profile.sh`, the new
`tools/scripts/fold_profile_duplicate_cost_selftest.sh`, its one-line
registration in `make fold-profile-selftest`, and this note. The other existing
changes in the checkout are not part of this slice. In particular, do not
stage the whole existing Makefile or fold-profile diff as this change.

The working-source baseline SHA-256 was
`5d8ace44df7a8da745865f5d2a46e322f4ad21e28eb68904c019f638f17aec71`.
Entry copies and the isolated incremental patch are retained in
`/tmp/worldstream-fold-duplicates/`. The baseline is the working source before
this slice, not HEAD, because earlier profiler improvements are uncommitted.

```sh
sh tools/scripts/fold_profile_duplicate_cost_selftest.sh --bench
sh tools/scripts/fold_profile_duplicate_cost_selftest.sh --baseline --bench /path/to/baseline.sh
make fold-profile-selftest fold-profile-summary-selftest
```

The regression checks duplicate keys around the window boundary, a key longer
than the window, malformed final occurrences, stage objects, first-line
selection and exact wide integers. It instruments actual duplicate-search
substring calls and bounds their total copied bytes for dense fixtures.
Without `--baseline`, the original reader fails this budget while returning
the same values; this negative control was exercised.

## Measurements

Linux x86_64, GNU awk 5.2.1, POSIX shell, warm tool/filesystem caches,
uncontrolled host load. Fixtures require no node, peer, network or datadir.
Each timing below is elapsed seconds for 20 uninstrumented parser reads.

| Duplicate fields | Baseline copied bytes/read | Candidate copied bytes/read | Baseline times | Candidate times |
| --- | ---: | ---: | --- | --- |
| 1,000 | 6,507,510 | 262,554 | 0.12 / 0.11 / 0.10 | 0.11 / 0.10 / 0.09 |
| 10,000 | 699,625,510 | 2,647,737 | 0.76 / 0.76 / 0.78 | 0.45 / 0.39 / 0.42 |

At 10,000 duplicates, copied bytes fall by over 99% and median elapsed time
falls from 0.76 to 0.42 seconds. This is a diagnostic stress case; ordinary
node responses need not contain this many duplicates.

The existing complete-sample benchmark (200 samples, five parser processes
each) measured baseline 4.46 / 4.78 / 4.84 seconds and candidate
4.97 / 4.60 / 4.84 seconds. These overlap and establish no ordinary-sample
speedup. The existing sparse-response benchmark (30 reads of a 2,155,651-byte
response) measured 2.59 seconds before and 2.21 seconds after in one pair;
no sustained sparse-case speedup is claimed.

## Validation and publication limits

`make fold-profile-selftest fold-profile-summary-selftest` passed, including
exact 50-column CSV, RPC failure/timeout rejection, parser work budgets and
wide summary counters. The new regression and complete-sample correctness
test also passed with mawk and BusyBox awk. POSIX/Bash syntax checks and
`git diff --check` passed. Direct architecture-tree, shell-host-assumption,
discarded-status and pipefail-status gates passed. `make lint-fast` exceeded
its 50-second bound during initialization; aggregate lint is not claimed green.
ShellCheck is unavailable. No C changed, so compiler checks are inapplicable.

The core seal verifies all 554 sealed files and 80 sections. This slice changes
no consensus, validation, optional acceleration policy, node runtime,
scheduling or database behavior. Its exact incremental diff contains only
source, test registration and this report; no secrets, production data,
binaries, logs, caches or benchmark output are included.

Publication is incomplete. Fetch cannot write `.git/FETCH_HEAD`; staging the
new test cannot create `.git/index.lock` because Git metadata is read-only.
Remote lookup also fails to resolve GitHub. No commit or push occurred, and
remote SHA equality was not verified. The required development branch and
entry HEAD remain unchanged.
