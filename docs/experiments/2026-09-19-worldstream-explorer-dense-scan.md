<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: dense explorer readiness scans

This slice reduces the cold-start benchmark observer's work on response bodies
containing many false `Latest Blocks` starts. It does not measure or claim an
end-to-end IBD improvement. No node, peer, production datadir, consensus rule,
validation path, acceleration policy or Hetzner-owned runtime was changed.

The starting checkout was already dirty on
`agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The baseline is the working file,
not that commit. SHA-256 of `tools/bench_fresh_sync.c`:

- Before: `665a816aac1caa9807f8e2cfd2209321ee4c6402685bc54158c6b80a65e735b7`.
- After: `316c415e466ad496817ee4475c92efd5081f11c278309718a9e09221877c00ce`.

The old observer compared the full marker at every byte in a 64-byte window.
Sparse windows now compare only their single possible start. Multiple starts
in a window select the library substring search over the remaining chunk.
The existing NUL-normalization helper preserves binary gaps by replacing NULs
with newlines; neither byte occurs in the marker. One extra buffer byte holds
the terminator. The 64 KiB read bound, 12-byte overlap, complete-response drain,
curl deadline and error checks are retained.

## Measurement

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, glibc 2.39, `-std=c23 -O2`,
warm local temporary files, no network. Each row is the median of three
measurements of five scans of a 16 MiB body. Counters are disabled for timing.
Host scheduling is uncontrolled; wall times are descriptive, not assertions.

| Body | Before, seconds | After, seconds |
| --- | ---: | ---: |
| No candidate | 0.012297 | 0.012291 |
| Repeated `L` | 0.049201 | 0.016893 |
| One `L` every 8192 bytes | 0.012721 | 0.012337 |
| Real marker at end | 0.010667 | 0.010564 |
| Real marker at beginning | 0.010102 | 0.010309 |
| Repeated `La` | 0.049129 | 0.016858 |

Dense cases are about 2.9 times faster in this fixture. Sparse comparisons
fall from 655,360 to 10,240 across five scans. Dense cases use 1,280 library
search calls across five scans instead of 83,886,020 explicit comparisons;
these counters do not count the library's internal comparisons. Every scan
still consumes exactly 16 MiB and uses 257 read calls including EOF.

## Reproduction and validation

```sh
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh --measure /path/to/before.c
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh --measure
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_sparse_marker_selftest.sh --analyze
make bench-fresh-sync-selftest
```

The new work assertion fails on the baseline. Focused tests and GCC
`-fanalyzer` pass, as does the complete `bench-fresh-sync-selftest` target.
Coverage includes all marker splits at 4 KiB and 64 KiB boundaries, dense
false starts followed by NUL-filled gaps, every NUL-interrupted marker split,
short bodies, sparse-window boundaries, complete draining, read errors and
failed transfers. Other observer fixtures now extract the reused helper.
Their acceptance conditions are unchanged. Shell syntax and `git diff --check`
pass. AddressSanitizer and UndefinedBehaviorSanitizer pass with leak detection
disabled because this runner's ptrace environment prevents LeakSanitizer.

The complete tool links using its Makefile recipe's compiler flags. A stricter
whole-tool `-Werror -pedantic` build fails identically before and after on
pre-existing omitted-middle `?:`, ignored `system` results and potentially
truncated copy commands. The changed scanner fixtures compile under
`-Wall -Wextra -Werror -pedantic`; these unrelated diagnostics were not waived
or repaired in this slice.

`timeout 60 make lint` exited 124 during prerequisite setup, after reporting
missing Tor archives and unchanged generated templates. No complete lint
verdict was obtained; full lint remains required before publication.

Git fetch cannot write `.git/FETCH_HEAD` because Git metadata is read-only.
Remote inspection also fails because `github.com` cannot resolve. Therefore
upstream integration, commit, push and remote SHA verification are unperformed.
Existing staged and unstaged work is preserved. Session-only baseline copies,
logs and binaries are under `/tmp/worldstream-explorer-guard/`, outside the
source slice. This change must not be committed together with unrelated work.
