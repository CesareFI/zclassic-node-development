<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream time-to-tip RPC observation status

Branch: `agent/worldstream-ibd-20260918`, HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Baseline is the working
`cold_start_to_tip_probe.sh` at session entry, including earlier pending work.
The instrument defect blocks trustworthy time-to-tip comparisons: a failed
`getblockchaininfo` command could print heights and still establish seeded
authority and a successful timed arrival at tip.

The smallest fix discards output on command failure and records a diagnostic
without RPC output or credentials. Sampling continues under the existing
deadline, so a later successful observation remains eligible. Height rules,
timestamp placement, cadence, and deadline comparisons are unchanged.

The regression extracts the shipped reader, parser, and complete polling loop
and supplies deterministic RPC, clock, process-liveness and sleep fixtures.
Linux x86_64, Bash; no real node, network, chain state or credentials are used.
All times below are fixture seconds, not host timings or measured IBD speedups.

| Case | Entry baseline | Fixed observer |
|---|---|---|
| Successful tip response | Tip at 1 s | Tip at 1 s |
| Tip-looking output, statuses 1, 7, 124 | False tip at 1 s in all three | No tip or seeded authority |
| Failed truncated output carrying both heights | False tip at 1 s | No tip or seeded authority |
| Failed call then successful retry | False tip at 1 s | Tip at 7 s |
| Arrival at exclusive 10 s deadline | Refused | Refused |
| Failed call at deadline | Refused | Refused |
| Empty or malformed height response | No tip | No tip |

Missing observations exhaust the fixture's 10 s budget at the next normal
poll, 12 s; this slice does not change sleep or timeout behavior. The new test
fails against the entry baseline at the first failed-command verdict.

Reproduce:

```bash
bash tools/scripts/cold_start_rpc_status_selftest.sh
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
# With the saved entry-state source:
bash tools/scripts/cold_start_rpc_status_selftest.sh --baseline /tmp/worldstream-rpc-observation/before.sh
bash tools/scripts/cold_start_rpc_status_selftest.sh /tmp/worldstream-rpc-observation/before.sh
```

The final command intentionally fails. The new ten-case regression is wired
into the existing probe selftest used by `mvp-coldstart-to-tip-local`.
The full probe selftest passes, including the existing 15-case height parser
and seed scan checks. Broader isolated checks pass:

- `cold_start_timing_selftest.sh`: five timing/threshold cases.
- `cold_start_snapshot_metadata_selftest.sh`: selection and metadata work budget.
- `c3_stopwatch_scratch_selftest.sh`: six repeat-run isolation cases.
- Bash syntax; tracked-tree discarded-status, pipefail-status and shell-host
  assumption gates; staged and unstaged `git diff --check`.

Tracked-tree lint does not cover the new untracked regression; it was separately
syntax checked and executed. `make lint-fast` exceeded a 45 s bound during
initialization, before a gate verdict. A real cold-start run is unavailable
because `build/bin/zclassic23` is absent. Full lint and live IBD acceptance are
not claimed. There is no compiled-code change requiring compiler analysis.

Owned changes: the RPC failure branch, one selftest invocation, the new
regression, and this note. Exact source review confirms no change to consensus,
normal independent validation, optional acceleration, peer/request scheduling,
databases, or node runtime. `git diff HEAD -- core` is empty. Earlier staged
and unstaged work is preserved. No generated artifacts, binaries, logs,
credentials or production data are part of this slice.

Entry probe SHA-256:
`71a88a682859311d880cb81275f27ef4bb7ba637b245ca76d0bb9fa0033ee0f9`.
Fixed probe SHA-256:
`627a6818a1c7adedf3b360858d334c0a8908148cda565cd0a71d9daebd794856`.

Publication remains blocked: `.git` is read-only, `git fetch origin main`
cannot write `FETCH_HEAD`, the local `origin/main` ref is absent, and
`git ls-remote origin` cannot resolve GitHub. No commit, push or exact remote
SHA verification occurred. Before publication, restore permitted Git metadata
writes and origin access, separate this slice from earlier pending edits,
fetch/integrate upstream, and complete required integration gates. Push only
the named development branch to origin and verify its exact SHA.
