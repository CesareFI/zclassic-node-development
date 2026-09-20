<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream benchmark startup credential observation

The fresh-sync benchmark accepted startup after a failed RPC-cookie open.
Empty, failed and oversized reads likewise supplied unusable credentials to
the polling loop. That loop could then consume the remaining 1,800-second
benchmark budget without useful RPC measurements. This is wasted benchmark
time, not evidence of a chain-processing bottleneck or an IBD speedup.

The startup reader now refuses these setup failures immediately, logs only
error metadata, and preserves successful newline-terminated, unterminated and
exact-fit reads. Its caller already exits on startup failure and cleans up
the benchmark child. The change does not add retries or alter the startup
waiting budget.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including existing pending work.
Before this slice, `tools/bench_fresh_sync.c` had SHA-256
`b68feb9dd81ebf754714c1068f511f46dd96c36d76fa2d503877100ccf1cb52b`;
afterward it has
`e404d3f5d67b2048d186e629ad3971fa3c358ffbbc1d8136c908f891c232982d`.
This slice changes only that file's cookie-reading block, extends the existing
startup selftest, and adds this note. Earlier pending work remains separate.

Reproduce with:

```bash
bash tools/scripts/bench_fresh_sync_startup_selftest.sh --analyze
```

The test compiles the production startup helper with a deterministic clock,
child and cookie fixtures. It uses no node, network, real credentials or
datadir. All 13 cases pass with GCC 14.2, C23 `-Wall -Wextra -Werror` and
`-fanalyzer`. Failed-open, empty, newline-only, oversized and read-error cases
return false with zero sleeps after cookie availability. The saved baseline
fails at the failed-open assertion because it returns true. The potential
1,800-second waste follows from the existing polling deadline; it was not
measured in a live run.

Direct phase-log, complete-log, command-output, height-demand, HTTP-deadline
and benchmark-outcome regressions pass. The observation-timing regression
fails identically against the saved baseline and updated source: it expects
completion at 21 seconds but observes 19 seconds. Its assertions are unchanged.
Both `make bench-fresh-sync-selftest` and `make lint-fast` exceeded a 50-second
bound during setup; neither aggregate is claimed green. The complete benchmark
builds with the target's compiler flags, with the existing five ignored-system
result warnings and two copy-command truncation warnings outside this slice.

Architecture, shell syntax, discarded-status and pipefail-status checks pass.
All 554 sealed core files and 80 sections verify. Exact diff inspection and
`git diff --check` pass. Consensus, independent validation, optional acceleration
and all Hetzner-owned runtime/scheduling/database surfaces are unchanged.
No secrets, binaries, logs, datadirs or temporary benchmark output belong to
this slice. The pre-existing staged diff is byte-for-byte unchanged.

Publication remains incomplete: Git metadata is read-only, `origin/main` is
absent locally, and querying origin fails on GitHub DNS. No commit, push,
upstream integration or remote-SHA equality is claimed. The branch remains
`agent/worldstream-ibd-20260918`.
