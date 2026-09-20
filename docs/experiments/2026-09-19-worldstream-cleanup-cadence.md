<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream benchmark shutdown polling under signals

Branch: `agent/worldstream-ibd-20260918`, starting HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The baseline is the
pre-slice working-tree `tools/bench_fresh_sync.c`, SHA-256
`4f29f6d7065067626d7dfc8039143617f129c25c9b5ed3dfa3d79e2ea357d321`.
Existing staged and unstaged changes are preserved. The slice owns only the
cleanup sleep retry, one Make test invocation, its new regression and this note.

The fresh-sync benchmark polled child status after every interrupted shutdown
sleep. With frequent signals this caused thousands of redundant `waitpid`
calls while the isolated child was shutting down. Retry the short sleep until
the next polling time or the existing 500 ms grace deadline. Reaping, SIGTERM,
SIGKILL, immediate exit detection and repeated-cleanup behavior are unchanged.
Sleep or scheduling delays can still extend observation beyond a deadline;
time spent handling signals counts toward the same grace period.

The deterministic fixture compiles the actual cleanup function with a virtual
monotonic clock and counted process/sleep calls. Linux x86_64, GCC 14.2.0,
`-std=c23 -O2 -Wall -Wextra -Werror -pedantic`; no node, network, datadir or
cache-sensitive input participates. One isolated child is simulated per case.

| Fixture | Before child polls | After child polls | Before / after duration |
|---|---:|---:|---:|
| No signals, child ignores TERM | 51 | 51 | 500 / 500 ms |
| Sleep interrupted every 100 microseconds, ignores TERM | 5,001 | 51 | 500 / 500 ms |
| Same interruptions, child exits at 25 ms | 251 | 4 | 25 / 30 ms |
| Each signal handler consumes 200 ms | 4 | 4 | 600 / 600 ms |

The interrupted forced-shutdown case eliminates 99% of child-status queries.
It still makes 5,000 interrupted sleep calls: signals themselves have a cost.
The graceful case trades excessive observation for the ordinary polling
cadence. This is benchmark observer overhead, not measured time-to-tip or
end-to-end IBD acceleration. Reported synchronization timings precede cleanup.

Reproduce against a saved pre-change source and the candidate:

```bash
bash tools/scripts/bench_fresh_sync_cleanup_cadence_selftest.sh --baseline /tmp/before.c
bash tools/scripts/bench_fresh_sync_cleanup_cadence_selftest.sh /tmp/before.c
bash tools/scripts/bench_fresh_sync_cleanup_cadence_selftest.sh
bash tools/scripts/bench_fresh_sync_cleanup_selftest.sh
make bench-fresh-sync-selftest
```

The baseline measurement succeeds; the regression fails on 5,001 polls.
The candidate passes, including strict compilation and GCC `-fanalyzer`.
The existing cleanup fixture passes unchanged, including real disposable
children: three 20 ms shutdowns were observed in 30.306, 30.219 and 30.320 ms
under uncontrolled host load. These wall times are descriptive, not gates.
All 51 `bench_fresh_sync*_selftest.sh` scripts pass individually, and
`make bench-fresh-sync-selftest` passes. Full benchmark compilation succeeds
with the same seven pre-existing warnings as the baseline. Bash syntax,
architecture-tree, pipefail-status, discarded-status, shell-host-assumption
checks and `git diff --check` pass. The shell gates inspect tracked files;
the new untracked fixture separately passes Bash syntax and strict compilation.

`make lint-fast` exceeded both 45-second and 120-second bounds during setup,
without producing a lint verdict. It is not claimed green. No acceptance
assertion was weakened.

Consensus and reducer sources match HEAD. This slice changes no node runtime,
validation, acceleration policy, peer/request scheduling, or database code.
All generated executables and measurement output remain outside the tracked
slice. Its four source/documentation files contain no credentials or runtime
state. Review shared files against the pre-slice tree, not their entire HEAD diff.

Publication is incomplete. Fetch fails because `.git/FETCH_HEAD` is read-only,
and querying the exact origin development branch fails to resolve GitHub.
The branch remains unchanged; no commit, push or remote-SHA verification is
claimed. Do not publish the unrelated pre-existing index as this slice.
