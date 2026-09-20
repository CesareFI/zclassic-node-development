<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: eliminate small-append observer read amplification

Scope: the standalone fresh-sync benchmark's phase-log opener, one isolated
regression, and its existing aggregate test registration. No node runtime,
consensus, validation, optional acceleration, scheduling, or database changes.

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.
The baseline is the existing dirty working-tree `tools/bench_fresh_sync.c`,
SHA-256 `633cc64a91bc10d2c532d10aab5ce59d01eaec5c37d12bb30362cf0144fa8680`.
The resulting source SHA-256 is
`84f71a6f54b5d031f9ec1cb6266bb18e17f7da341e5d134b85f272bd190b821c`.
Earlier uncommitted work is preserved and is a dependency of this small delta;
do not stage the entire source or Makefile as though it belongs to this slice.

## Problem and measurement

The previous opener selected a 4 KiB stdio buffer for small appends. A seek
on each reopened stream still read bytes preceding its unaligned saved cursor.
For the same file with at most 4096 unread bytes, the opener now selects
unbuffered I/O. Initial scans, replacement, truncation, unavailable metadata,
and larger backlogs retain bulk buffering. The scanner's independent size and
identity checks, scan budget, overlap, and milestone detection are unchanged.

Linux x86_64, GCC 14.2.0, C23 `-O2`, warm local temporary files, no node or
network workload: the existing growth fixture appends 100 bytes per poll for
10,000 polls. Three baseline trials read 21,443,467 / 21,443,483 / 21,443,483
bytes; changed trials read 1,000,107 / 1,000,122 / 1,000,122 bytes. This is a
95.3% reduction in kernel-accounted observer read bytes for 1,000,000 appended
bytes. Wall times were 0.097113 / 0.089768 / 0.089642 seconds before and
0.088265 / 0.080786 / 0.080626 seconds after; timing is not a pass threshold.
These are observer measurements, not an end-to-end IBD speedup claim.

The new regression exercises 1, 100, 4095, 4096, and 4097-byte appends starting
at an unaligned cursor. At or below 4096 bytes, it allows only the new payload
plus 4096 bytes of accounting overhead across 1000 polls. The saved baseline
fails this budget on the first case (501,599 bytes read for 1000 appended).
The change reads 1099 bytes. Exact cursors and every milestone split across
one-byte appends are checked, including transitions from bulk buffering.
Non-Linux hosts run behavior checks and explicitly report read accounting as
unobserved. The 4097-byte case retains its previous bulk read amplification;
it is a possible next independently measured slice.

## Validation

Passed:

- New small-append regression and existing growth, bulk-buffer, and idle-log
  fixtures, each with GCC `-fanalyzer` and warnings as errors.
- `make bench-fresh-sync-selftest` and `make build/bin/bench_fresh_sync`.
- Full-source C23 `-Wall -Wextra -Werror -fsyntax-only`.
- Shell syntax, architecture-tree, pipefail-status-pipe, discarded-status,
  `git diff --check`, and `git diff --cached --check`.

Bulk scanning retained 20,481 read syscalls for twenty 64 MiB scans. Idle
polling retained zero seeks and zero log reads. The fixtures also cover log
truncation/replacement, split markers, and buffering refusal.

Full-source optimized compilation/static analysis with warnings as errors
fails on existing ignored `system` results and copy-command truncation
diagnostics. The before/after diagnostics are identical after pathname
normalization. The ordinary build succeeds with those warnings. `make lint`
timed out after 60 seconds during prerequisites; full lint is incomplete.

## Publication state

No commit or push. Fetch failed because `.git/FETCH_HEAD` is read-only;
`git ls-remote origin` failed because `github.com` could not resolve.
`origin/main` is unavailable locally. The new test was staged successfully;
an attempt to unstage only that new file then failed because `.git/index.lock`
is read-only. Existing staged work was not modified. Local HEAD and the cached
development tracking ref agree, but this is not fresh remote verification.

The slice is the opener delta, one Make recipe line, the new small-append
selftest, and this note. Exact before-copies, patch, build/test logs, and
analysis output are under `/tmp/worldstream-small-append`, outside the commit.
No credentials, datadirs, generated artifacts, or production state belong to
this slice. Consensus and normal independent validation remain unchanged.
