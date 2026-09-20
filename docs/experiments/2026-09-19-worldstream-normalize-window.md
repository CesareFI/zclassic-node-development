<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: batch mixed binary/text log normalization

Scope: `tools/bench_fresh_sync.c` observer CPU cost, its regression, and the
existing `bench-fresh-sync-selftest` registration. No node, consensus,
validation, acceleration policy, peer scheduling, or database change.

The checkout began on `agent/worldstream-ibd-20260918` at
`c1f7863d098e1efaa8deba240c580ae0559312a5` with extensive staged and unstaged
work. The baseline is the pre-existing working source, not HEAD. Its SHA-256:
`52e7c7f1465246cb367c5e4b2c2109d0b4a3d5df1a2e870b253a6135f6483ba9`.
Only the normalization window and explanatory comment in that source change
in this slice. Existing work is retained.

## Problem and measurement

The phase/explorer observer converts embedded NULs to newlines before text
searches. A 64-byte window needs a library search for almost every NUL when
the gaps are 65 bytes. The new deterministic fixture observes 1,010 searches
per 65,536-byte input before the change and 254 afterwards. Ordinary text
still takes one search. All non-NUL bytes and buffer guards remain identical.

Use a 256-byte full window, retaining the bounded short-suffix loop. The
compiler can vectorize the fixed window; no allocation or ISA-specific code
is introduced. The 16 MiB polling budget and milestone semantics are intact.

Measured on Linux x86_64, AMD EPYC 7402P (48 logical CPUs), GCC 14.2.0,
`-std=c23 -D_DEFAULT_SOURCE -O2 -Wall -Wextra -Werror`. The existing
`bench_fresh_sync_nul_scan_selftest.sh` scans each freshly written 16 MiB
temporary file 20 times; these are warm local-file observations, without a
node, peer, datadir, or network transfer. Three alternating baseline/candidate
runs gave these median seconds:

| Input | Before | After |
|---|---:|---:|
| Text | 0.070801 | 0.070229 |
| Sparse NULs | 0.071874 | 0.071007 |
| Dense NULs | 0.087784 | 0.081950 |
| Paired NULs | 0.073665 | 0.071005 |
| NULs spaced 65 bytes apart | 0.109055 | 0.088103 |
| Alternating NUL/text | 0.085628 | 0.082371 |

The targeted input improves by 19.2%; the deterministic search count falls
74.9%. This is observer cost, not a measured end-to-end IBD speedup. The timing
candidate has the same executable statements as the final source, differing
only in its comment; its SHA-256 is
`b02b48bc3aaf820de1b59109ba24bfcdd78f833d697f28bc4b8b5a3dea83037f`.
Final benchmark source SHA-256:
`8184ca85dbd67f69c15e845f1f25292e488bac5158794dd986b09c535561b03f`.

## Validation and reproduction

Run the new fixture against a saved baseline and the changed source:

```sh
bash tools/scripts/bench_fresh_sync_normalize_window_selftest.sh /path/to/before.c
bash tools/scripts/bench_fresh_sync_normalize_window_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_nul_scan_selftest.sh --analyze
```

The baseline fails the work bound after passing byte checks; the changed
source passes. The new regression covers lengths 0 through 1,024, all 64
alignments, high-bit bytes, guards, and NUL gaps around both window sizes.
It is registered in the existing aggregate target. C23 compilation with
warnings as errors, GCC `-fanalyzer`, shell syntax, and `git diff --check`
pass. `timeout 60 make bench-fresh-sync-selftest` completes successfully,
including the new regression and the broader benchmark fixtures. The
following existing fixtures also pass individually:

- `bench_fresh_sync_selftest.sh`
- `bench_fresh_sync_sparse_marker_selftest.sh --analyze`
- `bench_fresh_sync_explorer_scan_selftest.sh`
- `bench_fresh_sync_binary_log_selftest.sh`
- `bench_fresh_sync_scan_budget_selftest.sh`
- `bench_fresh_sync_complete_log_selftest.sh`

Full-node build and publication are unverified. `make z23` encountered absent
Tor archives and could not register the Tor submodule because `.git/config`
is read-only; the build was interrupted. `timeout 60 make lint` exhausted its
budget during setup, without a lint verdict. Git fetch cannot write
`.git/FETCH_HEAD`; a read-only remote SHA query also fails because GitHub DNS
is unavailable. No commit, push, or verified remote SHA is claimed. No secrets,
node state, binaries, caches, or temporary benchmark output belong to this
slice. The isolated temporary fixtures are removed by their EXIT traps.
