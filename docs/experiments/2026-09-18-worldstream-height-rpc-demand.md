<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: suppress unused cold-start height observations

Scope: the RPC observer in `tools/bench_fresh_sync.c`. No node implementation,
consensus, validation, peer scheduling, database, custody or acceleration policy
changes. Z23 acceleration remains optional and independent validation remains
authoritative. This measures observer demand, not end-to-end IBD speedup.

## Baseline and deterministic measurement

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, on
`agent/worldstream-ibd-20260918`. The shared checkout had extensive existing
staged and unstaged work. An isolated checkout of that commit qualifies this
slice without incorporating those other changes.

The benchmark issued `syncstate` and `getblockcount` every polling iteration.
The height was consumed only when printing a changed state or first arrival
at tip. During a stable IBD state, every subsequent height response was unused.
Each production height request goes through `popen`, a shell, curl and node RPC.

The regression compiles the actual state-observation block and parsers with
counted fixture RPCs. It executes 100 stable polls, then state changes, a
missing state, a missing height and arrival at tip followed by stable tip polls.
It checks transition output as well as calls. No node, datadir or peer is used.

| Fixture observation | Baseline | Candidate |
|---|---:|---:|
| State RPCs in 100 stable polls | 100 | 100 |
| Height RPCs in 100 stable polls | 100 | 1 |
| State RPCs across all 116 polls | 116 | 116 |
| Height RPCs across all 116 polls | 116 | 5 |

The candidate demand assertion fails on the baseline. All five displayed
transitions retain their original height or missing-height sentinel. Counts
are deterministic; no wall-time, chain throughput or time-to-tip claim follows
from this fixture. Real latency savings depend on RPC and process costs.

## Change and reproduction

Move the height request inside the existing state-change branch. Keep every
sync-state observation, the polling sleep, phase observations, first-tip
handling, explorer readiness and validation-status diagnostics intact. Register
the regression as a prerequisite of the existing `bench_fresh_sync` target.

```bash
make bench-fresh-sync-height-selftest
bash tools/scripts/bench_fresh_sync_height_selftest.sh
bash tools/scripts/bench_fresh_sync_height_selftest.sh --analyze
```

The script accepts a source path to test another revision; `--analyze` requires
a compiler with GCC's analyzer. `--baseline` selects
the old demand expectations for measuring an unmodified source; normal test
and Make invocations always enforce the reduced demand.

## Validation

- Baseline failure and candidate pass, including exact transition output.
- C23 fixture compilation with `-O2 -Wall -Wextra -Werror -pedantic`, GCC
  `-fanalyzer`, and ASan/UBSan (leak detection disabled in this environment).
- Complete standalone benchmark compiled with its existing Makefile flags.
  A stricter full-file compilation exposed pre-existing GNU conditional,
  ignored `system` result and possible truncation diagnostics; the changed
  observer itself passes strict compilation and analysis. No warnings disabled.
- All 32 fast lint gates passed in the isolated checkout after resolving an
  initial complexity increase by reusing the existing branch, and avoiding
  shifted flag-registry line references by placing the new Make target last.
- Tracked shell syntax, discarded-status, no-Python and core-seal checks passed.
  All 554 sealed files and 80 sections match their manifest.
- Existing shared-worktree startup, command-output, HTTP-deadline and benchmark
  outcome fixtures passed with the candidate. Its observation-timing fixture
  also passed in a temporary copy with only the expected removed height-RPC
  costs subtracted: completion times 21/26/23 became 19/24/21 fixture seconds.
  The first-tip timestamps and grace-period predicate remained unchanged.
  Those prior uncommitted fixtures are not part of this isolated slice.
- Exact diff review and whitespace checks cover only source, test, Makefile
  registration and this experiment record. No generated outputs are included.

No production node or real-chain acceptance run was performed. A subsequent
measurement should quantify remaining `syncstate`/curl observer overhead under
real IBD load before changing observation cadence.
