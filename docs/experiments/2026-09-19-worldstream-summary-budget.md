<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound missing snapshot-summary observation

Branch: `agent/worldstream-ibd-20260918`; starting HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fresh-sync benchmark's display-only snapshot-summary lookup scanned the
entire child log backward when no `UTXOs in` marker existed. This synchronous
work delayed the next time-to-tip/deadline observation with cost proportional
to accumulated log size. The lookup now searches only the final 16 MiB and
prints an explicit unavailable diagnostic if the window has no match. Older
summaries outside that window are intentionally unavailable. Phase detection,
RPC observations, validation and benchmark success criteria are unchanged.

The baseline is the working source at entry, SHA-256
`ecd81edf829e51874f4a8f714b78e0ff52a0dc021e9775b7f53731bf790b3926`,
not pristine HEAD. The checkout already contained extensive staged, unstaged
and untracked changes, including the backward summary reader. This slice
changes only that reader's search window, adds a fixture and registers it in
the existing benchmark test target. Do not stage the whole dirty Makefile or
benchmark source as this slice. Baselines and its separate delta are retained
under `/tmp/worldstream-summary-budget/` as temporary development evidence.

## Measurement

Linux x86_64, GCC 14.2.0, `-O2`, real 256 MiB synthetic text file, no summary,
ordinary warm filesystem caches, three sequential observations per version.
No node, peer, RPC, production datadir or chain data participates. Ambient
host load is uncontrolled. Counted bytes are bytes returned by `fread`,
including seven-byte overlaps; they are not physical disk traffic.

| Observation | Baseline | Candidate |
|---|---:|---:|
| Bytes read per lookup | 268,550,137 | 16,784,377 |
| Wall seconds, three runs | .080496 / .078225 / .078506 | .003937 / .004456 / .004452 |

The deterministic read volume falls about 94%; median observer latency falls
about 94% on this fixture. This is not an end-to-end IBD speedup measurement.
The window bounds bytes searched, not storage-operation wall time.

## Validation and limits

`bench_fresh_sync_summary_budget_selftest.sh --baseline <source.c>` measures
the baseline without enforcing the new budget. Without `--baseline`, that
source fails the budget assertion. The candidate passes the budget, exclusion
of a marker one byte before the window, a marker exactly at the boundary,
chunk-split markers, latest-match selection, and small/empty logs. The existing
summary regression also passes missing/read-error, binary, oversized-line and
display-boundary cases.

All 24 scripts registered in `bench-fresh-sync-selftest` were run directly with
GCC 14 and passed. Bootstrap/epoch fixtures (31 and 34 cases) and output
visibility checks passed separately. The new regression passes GCC 14
`-Wall -Wextra -Werror -pedantic`, `-fanalyzer`, and Clang 20 strict compilation.
The existing summary regression passes GCC static analysis. Full benchmark
linking with the existing Makefile recipe succeeds; full-source Clang syntax
checking with `-Wall -Wextra -Werror` succeeds. Strict optimized GCC compilation
fails on seven existing ignored-`system`/format-truncation diagnostics, also
reproduced against the saved baseline; none was suppressed or changed.

Bash syntax, architecture-tree, shell-host-assumptions, pipefail-status,
discarded-status and `git diff --check` pass. `make lint-fast` exceeded a
50-second bound during initialization. No complete lint or node-suite pass is
claimed. No live IBD trial was run; the public binary is absent.

Consensus, cryptographic semantics, acceleration policy and Hetzner-owned
scheduling/database/runtime behavior are unchanged. The reviewed slice
contains only source, test registration, a fixture script and this record;
no credentials, datadirs, logs, caches or compiled artifacts are included.

Publication remains incomplete. Fetching the development branch fails because
`.git/FETCH_HEAD` is on a read-only filesystem; remote lookup also fails DNS
resolution. The aggregate lint gap remains open. No commit, push or verified
remote SHA is claimed.
