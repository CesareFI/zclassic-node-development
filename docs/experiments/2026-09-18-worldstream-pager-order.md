<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream sync-stall observer ordering cost

The external sync-stall pager insertion-sorted all canonical samples in its
retained ledger before evaluating progress. Reversed or reordered histories
therefore incurred quadratic observer work. This slice replaces only that
ordering step with a stable bottom-up merge sort: O(n log n) worst-case work,
O(n) scratch storage, and linear work on chronological input because already
ordered adjacent runs skip copying. All five sample columns move together;
equal timestamps retain append order. Alert thresholds, progress criteria,
announcement behavior and ledger parsing are unchanged.

The baseline is `tools/scripts/slo_page_if_stalled.sh` from
`c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. That file was clean before this slice. Its
SHA-256 is `0623b1de553ec51ccd19fa10145f7139709a2e1afe140917f392721bc0265510`;
the changed script is
`28d99cb7f92562afddbfd17d37b2f56d19f80742a7d4cd0fa4d4800283386345`.
Other pre-existing staged and unstaged work was preserved.

Measured on Linux x86_64, AMD EPYC 7402P, GNU awk 5.2.1. Each fixture contains
4,320 canonical samples (72 hours at the shipped 60-second cadence), one
retired-instance row and one empty object. Timing covers launching Bash and
the real extracted evaluator, including reading and evaluating the ledger.
Ordinary warm filesystem caches and ambient host load apply. Inputs are local;
there are no nodes, RPC calls, network transfers or announcements.

| Sample order | Baseline wall | Changed wall |
|---|---:|---:|
| Chronological | 0.393 s | 0.391 s |
| Reverse chronological | 6.034 s | 0.450 s |
| Older and newer halves exchanged | 3.245 s | 0.403 s |

This measures observer overhead, not end-to-end IBD acceleration. Reordering
is synthetic adverse input, not a claim about an observed live ledger.
Elapsed time is informational, never an acceptance threshold.

Reproduce from the repository root:

```sh
baseline=$(mktemp /tmp/zcl-pager-baseline.XXXXXX)
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/slo_page_if_stalled.sh > "$baseline"
bash tools/scripts/slo_page_order_selftest.sh --bench "$baseline"
bash tools/scripts/slo_page_if_stalled.sh --selftest
```

The new regression compares complete evaluator output against an independent
stable numeric sort in 46 cases: progress, flat heights, uncorroborated uptick,
outage, regression, null fields, sparse coverage, stale samples, conflicting
timestamp ties, four input orders and sizes around merge boundaries. Tied
newest rows deliberately trigger an alert to make the last-row diagnostic
fields observable. A mutation choosing the right run first on equal timestamps
fails the interleaved-ties fixture. The existing pager selftest invokes this
regression and separately covers exit codes, announcements and deduplication.

Both GNU awk and mawk pass the complete pager selftest using an isolated copy
with the unchanged HEAD evidence library. The hold and tip-agreement judge
selftests also pass. Bash syntax, architecture, core seal, shell-host
assumptions, discarded-status, pipefail-status-pipe, no-Python, no-API-keys,
no-warning-suppression, POSIX ERE and whitespace checks pass. The core seal
matches all 554 files and 80 sections. No consensus, cryptographic validation,
optional acceleration, peer scheduling, database or node runtime code changes.

Publication remains blocked. Fetch and staging fail because Git metadata is
read-only; querying the exact development branch fails because GitHub DNS is
unavailable. Full `make lint` fails during prerequisite preparation: zlib
cannot download, and the dev build subsequently reports incomplete compiler
output. The focused checks do not establish the full publication gate. No
commit, push or verified remote SHA is claimed.
