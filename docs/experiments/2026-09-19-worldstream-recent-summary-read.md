<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reduce recent snapshot-summary reads

The fresh-sync benchmark read 16 KiB to locate a snapshot summary even when
the summary ended its child's log. Start with a 512-byte window, then retain
64 KiB reads for older history and the existing total 16 MiB search budget.
Exhaust the small window's reverse search before falling back to older chunks;
this preserves the existing sparse and dense substring-search limits.

This changes display-only reporting in `tools/bench_fresh_sync.c`. It changes
no consensus, validation, acceleration policy, peer scheduling, database or
node runtime behavior. Z23 acceleration remains optional and independent
Zclassic validation remains authoritative. No live node was exercised.

## Baseline and measurement

Branch: `agent/worldstream-ibd-20260918`; starting HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The checkout already contained
substantial staged and unstaged work. The pre-edit benchmark SHA-256 was
`b5a6df8030d31a3194a3b771538b19667db12fdd474669321ba80f8b758c3c43`;
HEAD alone does not identify these baseline bytes.

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, C23 `-O2`, warm local temporary
fixtures and uncontrolled host load. The test compiles the actual scanner,
counts requested read bytes and calls, and measures monotonic elapsed time.
Each recent-summary repetition performs 2,000 lookups on a 65,544-byte file.

| Measurement | Before | After |
|---|---:|---:|
| Bytes read per recent-summary lookup | 16,384 | 512 |
| Read calls per recent-summary lookup | 1 | 1 |
| Recent-summary repetition 1 | 5.957 ms | 0.975 ms |
| Recent-summary repetition 2 | 5.957 ms | 0.957 ms |
| Recent-summary repetition 3 | 5.957 ms | 0.964 ms |
| Bytes over twenty absent-summary 16 MiB scans | 335,544,320 | 335,544,320 |
| Read calls over those twenty scans | 5,140 | 5,140 |
| Absent-summary median of three repetitions | 61.460 ms | 60.129 ms |

Recent-summary read volume falls 96.875%. Timing is descriptive, not a gate
or an end-to-end IBD claim. Older summaries can require an additional read
and up to 49,664 additional surrounding bytes compared with the former first
16 KiB window. The total byte budget stays unchanged. Binary bytes are still
refused within examined chunks; this reader does not certify the entire log
as text, and a smaller successful first read examines less preceding history.

## Validation and publication

```sh
bash tools/scripts/bench_fresh_sync_summary_chunks_selftest.sh --baseline /path/to/pre-edit.c
bash tools/scripts/bench_fresh_sync_summary_chunks_selftest.sh --analyze
make bench-fresh-sync-selftest
make build/bin/bench_fresh_sync
```

The baseline passes behavior checks in measurement mode and fails the new
512-byte read assertion without that mode. The candidate passes strict C23
`-Wall -Wextra -Werror -pedantic` and GCC `-fanalyzer` for the extracted actual
scanner. Regression coverage checks all marker splits at the new chunk
boundaries, recent-read bytes, and unchanged absent-search limits. The full
benchmark selftest target passes, including latest-match, partial-marker,
binary-log refusal, sparse/dense fallback and observation-budget cases.
The standalone benchmark builds; its seven warnings also reproduce on the
pre-edit source (ignored `system()` results and copy-command truncation).

Shell syntax and diff whitespace checks pass. Scoped lint passes architecture,
discarded status, pipeline status, warning suppression and shell host checks.
`timeout 60 make lint-fast` exits 124 during prerequisites, before reporting
gate results, so aggregate lint remains unverified. No full-node or real-chain acceptance is
claimed for this standalone reporting change.

Publication is blocked: `.git/FETCH_HEAD` is read-only, and the origin branch
lookup fails because GitHub DNS is unavailable. No commit, push, upstream
integration or remote-SHA verification is claimed. Preserve all prior work:
the coherent increment consists only of the scanner changes, changes to the
existing summary-chunks selftest, and this note. Temporary pre-edit copies,
measurement logs and the incremental patch are under
`/tmp/worldstream-summary-forward/`; they are not commit inputs.
