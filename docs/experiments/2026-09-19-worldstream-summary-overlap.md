<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Snapshot-summary reverse-scan overlap

Worldstream scope: benchmark instrumentation only. No node, consensus,
validation, acceleration policy, peer scheduling or database code changes.

The cold-start benchmark searches backward for the latest snapshot summary,
bounded to the final 16 MiB of its child's log. Each 16 KiB chunk also read
seven overlapping bytes to recognize split markers. On this host, those
extra bytes caused stdio to fetch an additional buffer per backward chunk.
Retaining those seven bytes in memory eliminates the repeated reads while
preserving the same search window, binary-log refusal and latest-match rule.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with pre-existing uncommitted work.
The actual pre-change `tools/bench_fresh_sync.c` SHA-256 was
`393eea7d6b69944979720adc60af2f27566f22dedaf28911d9ea9cd945ed466a`;
after this slice it is
`447bc76871d06b03fa22838dc8ee0db6b85889c22b97e54853f63efbe549a5eb`.
These identify source files, not published commits.

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, C23, `-O2`. Each sample searches
the same isolated 16 MiB text log twenty times with no matching summary,
warm ordinary page cache and ambient host load. No node or network runs.

| Measurement | Before | After |
|---|---:|---:|
| Bytes returned by fread, twenty scans | 335,687,540 | 335,544,320 |
| Read syscalls, twenty scans | 40,941 | 20,481 |
| Wall time, run 1 | 92.884 ms | 74.318 ms |
| Wall time, run 2 | 92.295 ms | 73.656 ms |
| Wall time, run 3 | 92.442 ms | 73.704 ms |

The syscall observations include the read of `/proc/self/io`. Wall time is
informational; the deterministic regression requires exactly one returned
copy of every scanned byte. The baseline fails that assertion. The median
observer time improves about 20%; this is not an end-to-end IBD speedup.

Reproduce with:

```sh
bash tools/scripts/bench_fresh_sync_summary_overlap_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_summary_overlap_selftest.sh --baseline /path/to/before.c
bash tools/scripts/bench_fresh_sync_summary_selftest.sh --analyze
ANALYZE=1 bash tools/scripts/bench_fresh_sync_summary_budget_selftest.sh
make -j2 bench_fresh_sync bench-fresh-sync-selftest
```

The focused tests cover every marker split, short final reverse chunks,
latest-match selection, oversized lines, binary logs, missing/read-failed
logs, and the 16 MiB search boundary. They pass with warnings as errors and
GCC `-fanalyzer`. The new test runs through `bench-fresh-sync-selftest`.

The standalone build and complete `bench-fresh-sync-selftest` target pass.
The build reports existing unchecked `system` calls and command-buffer
truncation warnings outside the changed function. Shell syntax and
`git diff --check` pass, as do the directly invoked architecture and pipefail
status-pipe gates (including the latter's selftest).
`make lint-fast` was interrupted during prerequisite work without gate
results; full lint acceptance is incomplete. No assertion or gate was relaxed.

Publication is unavailable in this session: Git metadata is read-only
(`git fetch` cannot write `.git/FETCH_HEAD`), and `git ls-remote origin`
cannot resolve GitHub. Existing staged and unstaged work is preserved;
no commit or remote-SHA verification is claimed.
