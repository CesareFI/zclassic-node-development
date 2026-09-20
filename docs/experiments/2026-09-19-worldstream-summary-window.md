<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound recent snapshot-summary candidate lookup

The fresh-sync benchmark's display-only snapshot-summary lookup called
`strrchr` over every byte of its 16 KiB / 64 KiB read buffer before its
bounded reverse comparison, even when the newest summary ended the buffer.
Check the final 64 bytes first, then retain the original whole-buffer lookup
when that suffix has no candidate. The last candidate, fallback search,
latest matching summary, binary-log refusal and read budget stay unchanged.

This slice changes only `snapshot_log_chunk`, registers a hermetic regression
in `bench-fresh-sync-selftest`, and adds this experiment. It changes no node
validation, consensus, acceleration policy, scheduling or database behavior.
Z23 acceleration remains optional; independent validation stays authoritative.

## Reproduction and measured scope

Measured on Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, `-O2`, warm in-memory
fixtures, uncontrolled host load, no node/network/datadir. Starting HEAD was
`c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`, with substantial pre-existing changes.
The exact pre-edit `tools/bench_fresh_sync.c` SHA-256 was
`adf55529bab5bb5dbde89e6f3fd609e0b622d00d0f09b6fbabc39e9262b7d3ac`.
HEAD alone does not identify this dirty baseline.

```sh
bash tools/scripts/bench_fresh_sync_summary_window_selftest.sh --baseline /path/to/pre-edit.c
bash tools/scripts/bench_fresh_sync_summary_window_selftest.sh
make bench-fresh-sync-selftest
make build/bin/bench_fresh_sync
```

The test counts the string extent presented to candidate search, separately
from timing with counting disabled. It compares all 33,153 short-buffer
position fixtures against a simple latest-match oracle, including empty
input, overlapping matches, suffix boundaries and trailing false candidates.
Large fixtures also exercise old-summary fallback and missing summaries.
Without `--baseline`, the pre-edit source fails the 64-byte search budget.

| Recent-summary fixture | Before | After |
|---|---:|---:|
| 16 KiB buffer: candidate-search extent | 16,384 bytes | 64 bytes |
| 64 KiB buffer: candidate-search extent | 65,536 bytes | 64 bytes |
| 200,000 helper lookups, 16 KiB, median of 3 | 43.367 ms | 2.436 ms |
| 200,000 helper lookups, 64 KiB, median of 3 | 160.312 ms | 2.438 ms |

The existing file-backed suffix fixture measured 6.656 ms before and
5.463 ms after for 2,000 lookups (medians of three). This is reporting work,
not an end-to-end IBD speedup. The no-summary 16 MiB fixture retained exactly
335,544,320 read bytes and 5,140 reads over 20 scans; observed medians were
56.613 ms before and 61.218 ms after. Those timings are not acceptance
thresholds, and no speedup is claimed for absent/old summaries.

## Validation and publication limits

The complete `make bench-fresh-sync-selftest` target passed, including the
new regression. `make build/bin/bench_fresh_sync` passed. The extracted real
helper passes C23 `-Wall -Wextra -Werror -pedantic` and GCC `-fanalyzer`;
shell syntax and `git diff --check` pass.

Scoped lint passed architecture ownership, pipeline-status preservation,
warning-suppression and live-lab-history checks. `make lint-fast` did not
complete: it was interrupted during prerequisites before emitting gate
results. Full lint is therefore unverified, not green.

A strict whole-file compile is not green: untouched code uses GNU omitted
ternary syntax, discards `system` results, and can truncate copy commands.
The saved pre-edit source reproduces the analyzer's ternary/truncation
failures. No warning suppression or unrelated repair is included.

Publication was unavailable in this session: `.git` is mounted read-only
(`git fetch origin main` cannot write `FETCH_HEAD`), and `git ls-remote
origin refs/heads/agent/worldstream-ibd-20260918` cannot resolve GitHub.
No commit, push or remote-SHA verification is claimed. Existing staged and
unstaged work is preserved. The baseline, logs and slice-only patch are local
temporary artifacts under `/tmp/worldstream-summary-window`, not deliverables
to commit.
