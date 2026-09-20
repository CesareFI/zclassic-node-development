<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream startup progress: bound underlying log reads

Worldstream scope: startup benchmark instrumentation. The startup progress
reader asks for only the final 256 bytes of its child's log, but buffered
stdio can read the preceding block while seeking. On a log ending one byte
before a 4 KiB boundary, each observation returned 4,095 bytes from the kernel.
Disabling buffering on this single-use stream reduces that to 256 bytes.
The log observation, line limits, error handling and node behavior are unchanged.
If disabling buffering fails, the reader logs that fact and retains its prior
behavior.

The slice adds four lines to `tools/bench_fresh_sync.c`, a hermetic regression,
and one invocation in `bench-fresh-sync-selftest`. Both existing files already
had unrelated uncommitted changes, which are preserved. Baseline is the working
file at entry, not pristine HEAD:

- Branch: `agent/worldstream-ibd-20260918`.
- HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`.
- Before source SHA-256:
  `447bc76871d06b03fa22838dc8ee0db6b85889c22b97e54853f63efbe549a5eb`.
- After source SHA-256:
  `ac5b57a93b587298cdaa64eb606457ee2ea4f5925d339d9be015c2571fffc687`.

## Measurements

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, C23, `-O2`. Each trial reads the
same isolated 67,112,959-byte sparse log 3,000 times, using ordinary warm
filesystem caches and uncontrolled ambient host load. Baseline trials ran
before candidate trials. No node, peers, RPC or production datadir participates.
`/proc/self/io` measures bytes returned by reads, including stdio read-ahead;
these are not physical disk I/O counters. Its own small accounting read is
included in each measurement.

| Trial | Baseline read bytes | Candidate read bytes | Baseline ms | Candidate ms |
|---|---:|---:|---:|---:|
| 1 | 12,285,103 | 768,102 | 20.643 | 18.401 |
| 2 | 12,285,108 | 768,106 | 20.532 | 18.253 |
| 3 | 12,285,108 | 768,107 | 20.545 | 18.262 |

Returned log bytes fall about 94%; median observer wall time falls about 11%.
This is a small instrumentation improvement, not an end-to-end IBD speedup.
The normal startup polling cadence makes the absolute saving small. Buffered
phase scans elsewhere remain buffered because they read large sequential ranges.

## Reproduction and validation

```sh
bash tools/scripts/bench_fresh_sync_tail_io_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_tail_io_selftest.sh /path/to/before.c
bash tools/scripts/bench_fresh_sync_progress_selftest.sh --analyze
make -j2 bench_fresh_sync bench-fresh-sync-selftest
```

The baseline passes boundary-value checks and fails the new kernel read-byte
budget. The candidate passes. Nine log extents cover short tails and buffer/page
boundaries. The existing regression also covers empty, unterminated, binary and
oversized lines, missing logs, and short reads. The resource observation reports
UNOBSERVED on hosts without `/proc/self/io`; value checks still run there. Only
Linux was measured in this slice.

The standalone build and complete benchmark selftest target pass. Both focused
fixtures compile with `-Wall -Wextra -Werror`; GCC `-fanalyzer` passes. The full
benchmark build retains existing unchecked `system` and command-buffer truncation
warnings outside this slice. Bash syntax, architecture-tree, pipefail-status,
discarded-status and shell-host-assumption gates pass. `git diff --check` passes.
`make lint-fast` exceeded a 50-second bound during prerequisite initialization;
aggregate lint acceptance remains incomplete. No gate or assertion was weakened.

The exact slice diff was reviewed. Consensus, cryptographic validation, optional
Z23 acceleration policy, and Hetzner-owned scheduling, database and runtime code
are unchanged. No secrets, logs, binaries, caches or generated output belong to
this slice. Temporary baseline snapshots and validation output remain under
`/tmp/worldstream-startup-tail/`.

Publication remains blocked: `.git` is read-only (`git fetch` cannot write
`FETCH_HEAD`), and GitHub DNS resolution fails. No commit or push was made and
no remote SHA was verified. Local HEAD and the existing remote-tracking ref
still agree, but that is not a fresh remote observation. Do not stage the full
dirty Makefile or benchmark source as this slice; they contain earlier work.
