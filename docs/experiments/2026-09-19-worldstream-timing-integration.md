<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream timing regression integration

Scope: complete the regression integration for the existing reduction in
fresh-sync height-RPC demand. Only
`tools/scripts/bench_fresh_sync_timing_selftest.sh` and this note changed in
this slice. Production code, consensus, validation, optional acceleration,
peer scheduling, databases and node runtime are unchanged.

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The checkout already contained
extensive staged, unstaged and untracked work. This qualification uses that
working tree, including its pending height-RPC and timestamp changes; it is
not qualification of the clean commit. Linux x86_64, GCC 14.2.0, isolated
deterministic C23 fixtures; no live node or network observation.

## Reproduction and measured cause

The timing regression failed immediately: normal completion was observed at
19 simulated seconds but its assertion expected 21. The old expectation
charged two seconds for a second height RPC even though the production loop
now requests height only on a state transition. Restoring that unused RPC
would slow observation and violate the separate demand regression.

The existing height regression independently passes and measures one height
request across 100 stable polls, and five across its 116-poll transition
sequence. Those are fixture request counts, not measured live IBD savings.
The blocked timing regression prevented completing the benchmark suite.

At the original two-second simulated height latency, correct timings are:

| Scenario | First tip | Explorer ready | Completion | Height requests |
|---|---:|---:|---:|---:|
| Normal | 11 s | 16 s | 19 s | 1 |
| First state observation missing | 17 s | 21 s | 24 s | 2 |
| First explorer observation fails | 11 s | 21 s | 21 s | 1 |

The fixture now checks exact height-request counts alongside those timestamps
and runs each scenario at zero-, two- and three-second simulated height costs.
Zero cost exposes the strict grace boundary: after a missing first state,
the third state observation is exactly five seconds after first tip and must
not complete the benchmark. The fourth observation completes at 23 seconds.
Both completion time and the latest state observation must be more than five
seconds after first tip. No production acceptance threshold was changed.

## Validation

Reproduce with:

```bash
bash tools/scripts/bench_fresh_sync_timing_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_height_selftest.sh --analyze
make bench-fresh-sync-selftest
```

- Nine timing cases pass with C23 `-O2 -Wall -Wextra -Werror` and GCC
  `-fanalyzer`; height demand also passes its strict compile and analysis.
- Three temporary source mutations fail runtime assertions: allowing exactly
  five seconds of grace, backdating the state observation to poll entry, and
  restoring height RPCs on stable polls. Compilation succeeds for each mutant.
- All 18 scripts named by `bench-fresh-sync-selftest` pass when invoked
  directly, covering startup, shutdown, interruption, log readers, HTTP
  bounds, readiness, timestamps, outcomes and diagnostic demand.
- Shell syntax, direct discarded-status, pipefail-status and shell-host-
  assumption gates pass. Tracked-tree gates do not cover the untracked test;
  its syntax and compiled fixture are checked directly.
- `make lint-fast` and `make bench-fresh-sync-selftest` each exceed a
  50-second bound during setup, before their gate/test verdicts. The direct
  no-wallclock-assertion scan exceeds a 20-second bound with no verdict.
  These are incomplete checks, not passes. Fixture clocks are synthetic.
- The existing tracked staged and unstaged diffs remain byte-identical to
  their entry snapshots. The incremental test diff was inspected separately
  because the test was already untracked. Whitespace checks emit no errors.
  No secrets, logs, binaries, caches or temporary outputs belong to this slice.

Production benchmark SHA-256 before and after:
`fa96727985b090831aa132db01c6f03dcc662a0933b1f121674bc8289377d940`.
Timing test before:
`579585ac8a3d62da99123867db0b6ba56cb85db952af681d3ed7666fb8148971`;
after: `be6e2d675e1cb982a12a6e06c08b9838963bde4e3219cf70426e8a8e4a3279e2`.

Publication remains incomplete. Fetch cannot write `.git/FETCH_HEAD`, and
staging this test cannot create `.git/index.lock`: Git metadata is read-only.
`origin/main` is absent locally; `git ls-remote origin` cannot resolve the
origin host. No commit, push, upstream integration or remote-SHA verification
was possible. No attempt was made to bypass these restrictions. Preserve the
earlier work when integrating; this test depends on its pending benchmark
changes. The next performance measurement remains real sync-state observer
cost under isolated IBD load; this slice makes no new end-to-end speed claim.
