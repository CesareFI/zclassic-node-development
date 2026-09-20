<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound repeated snapshot-summary searches

Owned delta: the fallback in `snapshot_log_chunk` in
`tools/bench_fresh_sync.c`, the new
`tools/scripts/bench_fresh_sync_summary_fallback_selftest.sh`, its invocation
in `bench-fresh-sync-selftest`, and this note. The extensive earlier staged,
unstaged and untracked work remains intact. In particular, the snapshot-log
reader is a pending prerequisite, not newly authored by this slice. Do not
stage the entire dirty benchmark source or Makefile as this slice.

Branch: `agent/worldstream-ibd-20260918`; HEAD at measurement:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.
The working-source baseline SHA-256 was
`53db8edd08290307e88ac8365272eccae7190ead594a12422151866793d56a6f`;
the candidate is
`98092e2897bab3031ee6ad41dda4b278dee861225a614ff83208bd5d8fa3be4a`.
This is qualification against that pending working tree, not pristine HEAD.

## Reproduction and change

The reader first tries a short reverse window near the last candidate byte.
If a trailing diagnostic moves that candidate beyond the window, the old
fallback enumerates every earlier matching summary. A 64 KiB synthetic buffer
with repeated summaries and a 512-byte unrelated suffix requires 4,065
substring searches per lookup.

Keep the first eight linear searches for sparse logs. When those all match,
bisect the remaining possible start positions. A successful suffix search
advances the latest match; an unsuccessful search excludes all starts in that
suffix. The previously checked reverse window bounds the upper end. This
preserves the latest-match policy, including partial final markers, without
allocating memory or altering the text. The existing 16 MiB file-read budget,
line-size checks and refusal behavior are unchanged.

## Measurement

Linux x86_64, GCC 14.2.0, C23 `-O2`, warm synthetic in-memory buffers, three
sequential repetitions per case, uncontrolled ambient host load. Each timing
covers 1,000 lookups of 65,536 bytes. Both versions use the same search-count
instrumentation. No node, RPC, peer, production datadir or network participates.

| Buffer | Baseline searches | Candidate searches | Baseline seconds | Candidate seconds |
|---|---:|---:|---|---|
| No summary | 1,000 | 1,000 | .009514 / .008598 / .008582 | .008556 / .008554 / .008586 |
| One early summary | 2,000 | 2,000 | .008614 / .008600 / .008608 | .008608 / .008580 / .008574 |
| Dense summaries, unrelated suffix | 4,065,000 | 24,000 | .195416 / .196138 / .196317 | .002709 / .002686 / .002700 |
| Dense summaries, match at end | 0 | 0 | .001150 / .001154 / .001150 | .001151 / .001153 / .001155 |
| Seven early summaries | 8,000 | 8,000 | .008829 / .008894 / .008929 | .009286 / .009971 / .009388 |

The dense-suffix fixture's median observer cost fell about 98.6%. The sparse
seven-summary fixture was slightly slower despite identical search counts;
these measurements establish no universal speedup. In particular, bisection
can revisit a long nonmatching suffix after eight matches. Real log density
and end-to-end IBD impact remain unmeasured. This display reader does not
establish snapshot validity or sovereign validation completion.

## Validation

```bash
bash tools/scripts/bench_fresh_sync_summary_fallback_selftest.sh --analyze
make bench-fresh-sync-selftest
```

- The new regression compares 10,010 boundary/density/suffix cases with an
  independent linear oracle, then checks search budgets for five workloads.
  It passes C23 `-Wall -Wextra -Werror -pedantic` and GCC `-fanalyzer`.
- The entry source fails the new dense-fallback search budget. A compiled
  mutation that treats every bisection probe as absent fails the offset oracle.
- `make bench-fresh-sync-selftest` passes, including bootstrap, epoch and receipt
  prerequisites and all 38 recipe scripts. The 38 scripts also pass when run
  directly. Related tests cover bounded file reads, latest summaries, marker
  splits, oversized lines, binary logs, short reads and refusal behavior.
- Bash syntax, architecture-tree, direct discarded-status, pipefail-status and shell-host-assumption
  checks pass. `git diff --check` passes. No wall-time threshold grades the new
  regression; the timeout only bounds a hung test process.
- A strict whole-file compile/static-analysis attempt fails on two existing
  `snprintf` truncation warnings in unrelated copy-command construction. The
  exact entry source reproduces both warnings. They were not suppressed or
  changed. No successful full-node build or live-chain acceptance is claimed.
- Aggregate `make lint-fast` remains incomplete: attempts exceeded 50 and
  180 seconds during initialization, before gate verdicts.

The incremental diff changes only observer tooling and its regression wiring.
Consensus, proof-of-work, cryptographic validation, optional acceleration
policy, peer scheduling, database tuning and node runtime are untouched.
No secrets, wallets, logs, caches, binaries or generated outputs belong to the
slice. Entry snapshots and temporary measurement output are under `/tmp`.

## Publication status

Required integration is incomplete. Initial fetch attempts encountered
read-only Git metadata; a later fetch and staging of the new test succeeded.
Separate origin lookups still failed DNS resolution. `origin/main` does not
exist on this origin. The final fetch retry again failed because Git metadata
was read-only. No commit, push or exact remote-SHA verification is claimed.
The pending reader prerequisites and unrelated staged work must be separated
before publication; the test alone is not a coherent clean-HEAD commit.
Earlier staged changes were compared byte-for-byte against the entry snapshot,
excluding only the newly staged test. Unrelated unstaged diffs also compare
identically. The isolated source/Makefile patch is
`/tmp/worldstream-summary-slice.patch`.
