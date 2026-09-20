<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound phase-observer reads for two-block appends

Scope: `tools/bench_fresh_sync.c` and its existing small-append selftest.
The benchmark's reopened phase-log stream now uses unbuffered I/O for up to
8192 unread bytes instead of 4096. This needs at most two 4 KiB scanner reads;
larger backlogs retain 64 KiB buffering. Identity, truncation, milestone
matching, scan budgets, and optional acceleration behavior are unchanged.
No consensus, validation, peer scheduling, or database code changed.

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.
The baseline is the existing dirty working-tree source, SHA-256
`a4529b197298e7a6df8f1ec11a38d162fdd7e16be67b82309a86e1a06623a2d1`.
The changed source is SHA-256
`271269a247dc0ecf4d392db2ed5c60e326e647fc73a05e9c6e3d974e43a32932`.
Earlier uncommitted work is preserved and is a dependency of this delta;
staging the entire source or test would include prior slices.

## Reproduction and measurement

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, C23 `-O2`, local warm-cache temporary
logs, no node or network workload. Each case appends 1000 times to an unaligned
cursor. `/proc/self/io` measures reads, including a small accounting overhead.

| Bytes per append | Before read bytes | After read bytes | Read syscalls before / after |
|---:|---:|---:|---:|
| 4097 | 35,252,084 | 4,097,120 | 2002 / 2002 |
| 8191 | 44,556,624 | 8,191,124 | 2002 / 2002 |
| 8192 | 36,865,124 | 8,192,124 | 2002 / 2002 |

At 4097 bytes per append this removes 88.4% of observer read bytes. Three
before/after trials reproduce the 4097- and 8192-byte accounting exactly.
The 4097-byte timings were 0.016607 / 0.016597 / 0.016558 seconds before and
0.014927 / 0.014400 / 0.014585 seconds after. Timing is descriptive, not a
test threshold or an end-to-end IBD speedup claim.

The extended existing regression checks byte and syscall budgets for 1, 100,
4095, 4096, 4097, 8191, and 8192-byte appends. An 8193-byte control retains bulk
buffering. Every case verifies exact cursors and all milestones split across
one-byte appends. The saved baseline fails at the new 4097-byte read budget;
the changed source passes. Hosts without `/proc/self/io` still check behavior
and explicitly report read accounting as unobserved.

Reproduce with:

```bash
bash tools/scripts/bench_fresh_sync_small_append_selftest.sh --analyze
make bench-fresh-sync-selftest
```

## Validation and limits

Passed: the aggregate benchmark selftest target; small-append, bulk-buffer,
idle-log, and growing-log fixtures with GCC `-fanalyzer` and warnings as errors;
full-source C23 syntax with `-Wall -Wextra -Werror`; standalone benchmark build;
shell syntax; direct architecture-tree and pipefail-status-pipe gates;
`git diff --check` and `git diff --cached --check`.

Bulk scans retain 20,481 read syscalls for twenty 64 MiB scans. Idle polls
retain zero seeks and zero log reads (one accounting read). Optimized full-source
analysis with warnings as errors fails on the same pre-existing ignored
`system` results and copy-command truncation diagnostics before and after.
The normal build succeeds with these warnings. `make lint-fast` times out
after 60 seconds in prerequisites. The combined architecture/pipefail Make
invocation was interrupted in prerequisites; both underlying gates passed
when invoked directly. Full lint is incomplete. No live IBD was run.

Appends above 8192 bytes retain bulk buffering and may still reread old bytes;
that remaining tradeoff needs independent byte, syscall, and timing measurement.

## Publication state

No commit or push: `.git/FETCH_HEAD` is read-only, and the read-only remote
query cannot resolve `github.com`. `origin/main` is unavailable locally. HEAD
and the cached development tracking ref agree, but this is not current remote
verification. The branch and existing index are untouched.

Before-copies, the exact incremental patch, and test/build logs are under
`/tmp/worldstream-medium-append`, outside the commit. This slice contains only
source, regression, and this note; no secrets, datadirs, binaries, or benchmark
output are intended for publication. Independent Zclassic validation remains
authoritative and unchanged.
