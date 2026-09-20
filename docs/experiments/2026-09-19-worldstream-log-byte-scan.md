<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream phase-log byte scan

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Earlier staged and unstaged
Worldstream work is preserved. The baseline is the working-tree benchmark
before this slice, not clean HEAD. Linux x86_64, GCC 14.2.0, local temporary
fixtures and ordinary warm filesystem caches; ambient load is uncontrolled.
No node, network, chain data or production datadir participates in the tests.

The fresh-sync phase scanner visited every byte with a scalar loop to replace
NULs before searching for milestones. Ordinary text now uses a bounded
`memchr` first. If a NUL exists, the same scalar normalization runs from that
byte through the remaining buffer. Dense binary input therefore retains a
single scalar suffix walk rather than invoking a search for every NUL.
Read boundaries, overlap, offsets, milestone matching, error handling and
polling semantics remain unchanged.

Three runs of the existing absent-marker workload, each making 20 polls of a
16 MiB text log, read exactly 16,777,216 bytes in 4,096 reads in both versions:

| Run | Before, seconds | After, seconds |
|---|---:|---:|
| 1 | 0.016412 | 0.005930 |
| 2 | 0.016046 | 0.006075 |
| 3 | 0.017442 | 0.005922 |
| Median | 0.016412 | 0.005930 |

This is about 64% less measured scanner time on this text fixture. It is not
an end-to-end IBD improvement or a time-to-tip result. Read volume is unchanged,
and a large backlog with missing milestones still requires scanning all newly
available bytes. Binary-log throughput was not benchmarked.

Source SHA-256 before:
`bd90cb3bbdd52a115b7714b03a770d38f614b697b86a1e17bf9d192b6471c48d`;
after: `7f8352cbcceca1cccf8c168bfd296b3f981e621546a9a9323e3b9c93dba06b89`.

Reproduce with a saved pre-change source:

```bash
bash tools/scripts/bench_fresh_sync_selftest.sh /tmp/before.c
bash tools/scripts/bench_fresh_sync_selftest.sh
bash tools/scripts/bench_fresh_sync_binary_log_selftest.sh /tmp/before.c
bash tools/scripts/bench_fresh_sync_binary_log_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_complete_log_selftest.sh --analyze
```

The new regression compiles the actual scanner and covers all 256 byte values,
every NUL position in a 4 KiB block, dense NUL input, real markers across read
boundaries, and every internal marker split separated by a NUL. Both baseline
and changed source pass. A mutation that removes normalization fails the
milestone assertion. Timings remain descriptive, without wall-clock thresholds.

Validation:

- The focused tests pass with C23 `-Wall -Wextra -Werror -pedantic`; GCC
  `-fanalyzer` passes for the binary-log and complete-log fixtures.
- Direct execution of the twelve `bench_fresh_sync_*selftest.sh` scripts
  yields eleven passes. The timing regression fails identically against the
  saved baseline and changed source: its first case expects `t_done=21`, but
  observes 19. The two failure logs are byte-identical. No assertion changed.
- Both complete benchmark executables compile. They retain the same seven
  pre-existing warnings: five unchecked `system` results and two potentially
  truncated copy commands. No warning is suppressed.
- `make bench-fresh-sync-selftest` and `make lint-fast` each exceed a 50-second
  bound during initialization, after unchanged template generation and a
  missing-Tor-archives warning. Neither aggregate is claimed green.
- Direct architecture-tree, pipefail-status, discarded-status and shell-host
  gates pass. Tracked-file scans do not include the new untracked test; its
  Bash syntax and compiled checks pass separately. `git diff --check` passes.

Owned changes are the NUL scan in `tools/bench_fresh_sync.c`, one test invocation
in `Makefile`, the new binary-log selftest and this note. The incremental diff
against the saved working tree was reviewed. No secrets, logs, caches, binaries,
generated artifacts or temporary benchmark output belong to the slice.
Consensus source has no diff. Node validation, optional acceleration policy,
peer/request scheduling, database behavior and node runtime are unchanged.

Publication remains incomplete. Fetching the authorized branch fails because
`.git/FETCH_HEAD` is read-only; querying its actual origin ref fails DNS
resolution. `origin/main` is absent. No commit or push is claimed, and cached
remote-tracking equality is not independent remote verification. Staging only
the two new files also failed to create `.git/index.lock` on the read-only
filesystem; the pre-existing index was left unchanged. Earlier dirty
phase-scanner work is also an integration prerequisite: do not commit
the entire dirty benchmark or Makefile as though it belonged to this slice.
Finish aggregate validation and separate the earlier work before publication
from an environment with writable Git metadata and working origin access.
