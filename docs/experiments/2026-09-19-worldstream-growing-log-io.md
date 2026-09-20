<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reduce growing phase-log read amplification

This slice changes only the standalone fresh-sync benchmark observer, its
fixtures, and test registration. No node runtime, peer scheduling, database,
consensus, validation, or optional acceleration behavior changes.

The starting branch is `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Substantial pre-existing dirty work
is retained. The immediate baseline is the working-tree
`tools/bench_fresh_sync.c`, SHA-256
`b7689fd142691bf8c618cb8b124a1bf728880efe247550b611dc91f9f636bc3c`,
not the file at HEAD. The resulting source SHA-256 is
`ee8d86c475f4e9d244f8d2cd642088fdf77956db6556139e3502ca930be099a9`.

## Measured problem and change

The phase observer reopens its log with a 64 KiB stdio buffer. Seeking to an
unaligned saved cursor can reread the preceding partial stdio block, even
when only 100 bytes have been appended. Idle-poll avoidance does not address
this growing-file case.

The opener now selects a 4 KiB buffer when the same file has at most 4 KiB
of unread data. Initial scans, replacements, truncations, larger backlogs,
and unavailable sizing observations retain the 64 KiB buffer. The scanner
still independently checks identity and size, preserves split markers,
and enforces the existing per-poll scan budget. The extra metadata lookup
only selects buffering; it never establishes a phase observation.

The new regression compiles the actual opener and scanner. It creates a
128 KiB log, then appends 100 bytes before each of 10,000 observations, with
exact cursor and missing-marker assertions. A split marker across subsequent
polls must still be detected. The baseline fails the new read budget.

Measured on Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, C23 `-O2`, warm local
temporary files, one fixture process and no node/network workload:

| Version | Kernel-accounted read bytes, three trials | Wall seconds |
|---|---|---|
| Baseline | 324572043 / 324572060 / 324572060 | 0.100554 / 0.100282 / 0.100448 |
| Changed | 21443467 / 21443483 / 21443483 | 0.097470 / 0.089646 / 0.089300 |

The fixture appends 1,000,000 bytes per trial. Read accounting includes the
small `/proc/self/io` observation. Read amplification falls about 93.4%.
Wall time is reported, not used as a flaky threshold. The extra `fstat` has
a cost: the unchanged-log fixture took about 0.051 seconds per 10,000 polls
versus 0.049 seconds on the baseline, with zero seeks and no log reads in
both cases. Large-backlog acceptance retained 20,481 read syscalls for twenty
64 MiB scans. These are observer microbenchmarks, not measured chain IBD or
time-to-tip improvements. Other platforms report kernel read accounting as
unobserved when `/proc/self/io` is unavailable.

## Validation

Passed:

```sh
bash tools/scripts/bench_fresh_sync_growth_io_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_buffer_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_idle_log_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_timing_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_expired_observers_selftest.sh --analyze
make bench-fresh-sync-selftest
make build/bin/bench_fresh_sync
bash tools/lint/check_architecture_tree.sh
git diff --check
```

The three extracted-loop fixtures only gain the POSIX feature declaration
and stat header required by the actual opener; their assertions are unchanged.
Shell syntax and full-source strict syntax checking passed. Strict optimized
full-source compilation/static analysis is blocked by existing ignored
`system` results and copy-command truncation warnings. The saved baseline
produces identical diagnostics after normalizing its pathname. Focused
fixtures compile with `-Wall -Wextra -Werror` and pass GCC `-fanalyzer`.
`make lint-fast` timed out after 60 seconds during prerequisites; it is an
incomplete gate, not a pass.

## Publication boundary

No commit or push was possible: `.git/FETCH_HEAD` is read-only, and the
read-only remote lookup cannot resolve `github.com`. `origin/main` is not
available locally. The local branch and cached development-branch tracking
ref still point to the starting SHA; this is not fresh remote verification.
No permission bypass or alternate Git metadata store was used.

This slice consists of the opener change, one Make recipe line, the new
growth fixture, two C preamble lines in each of the timing/outcome/expired
observer fixtures, and this note. Full-file staging would include earlier
unrelated work and must not be used. Exact before-copies, patch, compiler
output and benchmark logs are under `/tmp/worldstream-growing-log`; none
belongs in a commit. No secrets, datadirs, or production state were touched.
