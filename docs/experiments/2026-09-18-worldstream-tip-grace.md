<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: consecutive tip observations in the cold-start benchmark

The fresh-sync benchmark could report "Fully operational" after its first
`at_tip` observation even when later polls returned `syncing` or failed. This
undercounted cold-to-live time and accepted runs that never recovered. The
slice corrects measurement validity; it does not demonstrate faster IBD.

The benchmark now tracks the start of the current sequence of at-tip
observations separately from first arrival. Any other state, including the
`unknown` left by an unsuccessful RPC, resets that interval. Completion needs
the existing explorer milestone and greater-than-five-second grace period
after the current sequence began, as measured at completion of the latest
tip observation. Time spent in unrelated observers cannot satisfy the grace
period. First-tip reporting remains unchanged.
Polling establishes observations, not continuous liveness between polls;
explorer availability remains a first-observation milestone.

The existing outcome regression compiles the actual production poll loop and
result path with deterministic clocks and observers. No node, network,
credentials or production datadir participates. Seven added cases establish:

| Observation sequence | Baseline | Corrected |
|---|---|---|
| First tip at 10 s, then syncing permanently | Success at 16 s | Timeout, failure |
| First tip at 10 s, syncing, recovered tip at 16 s | Success at 16 s | Success at 22 s |
| First tip at 10 s, then RPC fails permanently | Success at 16 s | Timeout, failure |
| First tip at 10 s, RPC failures, recovered tip at 16 s | Success at 16 s | Success at 22 s |
| First tip at 10 s, syncing, recovered tip at 28 s | Success at 16 s | Timeout, failure |
| First tip at 10 s, explorer completes at 17 s | Success at 17 s after one tip poll | Success at 19 s after another tip poll |
| First tip at 23 s, latest tip poll at 25 s, explorer completes at 30 s | Success at 30 s | Timeout, failure |

The fixture budget is 30 s with two-second polls. Recovered cases retain the
10-second first-tip timestamp. The inclusive deadline case now explicitly
completes its second tip observation at 30 s, covering the grace interval,
and still requires success. Its former timing is retained as the last row
above. All other existing deadline/outcome cases retain their expectations.
Independently removing the reset or restoring the old grace-time comparison
causes the regression to fail.

Reproduce the focused check:

```bash
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze
```

Baseline: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including the prior pending work.
Baseline `tools/bench_fresh_sync.c` SHA-256:
`e404d3f5d67b2048d186e629ad3971fa3c358ffbbc1d8136c908f891c232982d`.
Updated SHA-256:
`42fde8f45b69d7643cd9d75763a74277a0d0f32e54e3fa29256c725c37c68a1c`.
This slice owns only the grace tracking/comparison in that file, the seven
new cases and inclusive-deadline timing in the existing pending outcome
selftest, and this note. No
Makefile change is needed: its pending aggregate already invokes that test.

On Linux x86_64 with GCC 14.2, all 13 outcome cases pass with C23
`-Wall -Wextra -Werror` and GCC `-fanalyzer`. Phase-log, complete-log,
startup-cookie, command-output, HTTP-deadline and height-RPC regressions pass
directly. The full benchmark compiles; it retains seven pre-existing warnings
about ignored `system` results and possibly truncated certificate-copy commands.

Broader checks are incomplete. The existing timestamp selftest fails on both
the saved baseline and modified source: its first fixture expects completion
at 21 s, but both produce 19 s. Its assertion is unchanged. Both
`make bench-fresh-sync-selftest` and `make lint-fast` exceed a 50-second bound
during setup before their aggregate recipes run; neither is claimed green.
Architecture, shell syntax, discarded-status, pipefail-status,
shell-host-assumption, secret-printf, no-Python and real-clock-test gates pass.
Exact diff inspection and `git diff --check` pass. All 554 sealed
core files and 80 sections verify, and the seal-root mirror matches.

Consensus, independent validation, optional acceleration, peer scheduling,
databases and node runtime are unchanged. The diff contains source, fixture
code and this note only; no logs, binaries, credentials or datadirs belong to
it. Earlier staged work remains byte-for-byte unchanged.

Publication is blocked: `.git` is read-only, fetching cannot write
`FETCH_HEAD`, `origin/main` is unavailable locally, and querying origin fails
on GitHub DNS. No commit, push, upstream integration or remote-SHA equality
is claimed. The current branch is unchanged.
