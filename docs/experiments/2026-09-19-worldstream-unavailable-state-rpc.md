<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Avoid a redundant height RPC after an unavailable sync-state observation

Worldstream scope: cold-start benchmark observation cost. No node runtime,
peer scheduling, database, consensus, or validation code changes.

The benchmark previously requested `getblockcount` whenever its displayed state
changed, including a failed `syncstate` request becoming `unknown`. With an
unavailable endpoint, both requests could consume their two-second curl limits.
The second request supplied no usable height in that case and delayed the next
phase/deadline observation. Repeated `unknown` polls already skipped height.

The height request now requires a successful state request and string extraction.
Failed observations still display `unknown` with height `-1`, break the existing
tip stability interval, and cannot establish readiness. Recovery to a valid
state still requests height. All acceptance thresholds remain unchanged.

## Reproduction and result

The isolated regression extracts the production state-observation block and
parsers. Its deterministic clock charges each unavailable RPC two seconds;
it uses no network, real node, or persistent datadir. This measures modeled
observer blocking, not wall-clock IBD throughput or full-chain time to tip.

| Previous state | Baseline RPCs / seconds | Changed RPCs / seconds |
| --- | --- | --- |
| First observation | 2 / 4 | 1 / 2 |
| Syncing | 2 / 4 | 1 / 2 |
| At tip | 2 / 4 | 1 / 2 |
| Already unknown | 1 / 2 | 1 / 2 |

The new assertions failed against the original source. `--baseline` reproduced
the old counts. Repeated failures and recovery are also checked. The existing
116-poll demand fixture now makes four height calls instead of five; all valid
transition heights remain checked. Nine existing integrated timing cases keep
the strict greater-than-five-second tip grace requirement and exact timestamps.

Baseline checkout: `c1f7863d098e1efaa8deba240c580ae0559312a5`, with extensive
pre-existing modifications. Baseline `tools/bench_fresh_sync.c` SHA-256:
`271269a247dc0ecf4d392db2ed5c60e326e647fc73a05e9c6e3d974e43a32932`.
Changed source SHA-256:
`b5a6df8030d31a3194a3b771538b19667db12fdd474669321ba80f8b758c3c43`.
Fixture compiler: GCC 14.2.0 on Linux; no cache, topology, or disk-throughput
claim is made by this synthetic clock fixture.

## Validation

Passed:

```sh
bash tools/scripts/bench_fresh_sync_unavailable_rpc_selftest.sh
bash tools/scripts/bench_fresh_sync_height_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_timing_selftest.sh --analyze
make bench-fresh-sync-selftest
make bench_fresh_sync
git diff --check
```

The focused fixtures compile with C23, warnings as errors, and GCC `-fanalyzer`.
Shell syntax checks pass. A strict whole-driver compile fails on existing
unchecked `system()` results and potentially truncated certificate-copy commands;
the exact saved pre-change source reproduces those diagnostics. The normal
Makefile build passes. No live IBD or consensus-parity acceptance was attempted.

Architecture passes through `tools/lint/check_architecture_tree.sh`. The
Make-based lint and architecture invocations stalled before a verdict and were
interrupted. Running the configured 32 fast-lint gates directly completed with
28 passes and four failures: root-entry policy rejects the environment's
`.agents` and `.codex`; complexity exceeds existing limits in the already
modified benchmark/probe functions (this change adds one condition in `main`);
37 flag-registry first-use line pointers are stale in the dirty tree; and the
Windows guard cannot create scratch under the read-only home state directory.
These are unresolved integration failures, not a green lint result. No limits,
baselines, or assertions were weakened to bypass them.

Publication is unavailable in this session: `.git` is read-only (fetch cannot
write `FETCH_HEAD`), and `git ls-remote origin` cannot resolve `github.com`.
The branch remains `agent/worldstream-ibd-20260918`. No commit, push, or remote
SHA verification is claimed. Existing staged and unrelated work is preserved.
