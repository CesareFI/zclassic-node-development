<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream explorer polling during renewed synchronization

Branch: `agent/worldstream-ibd-20260918`. HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Linux x86_64, GCC 14.2.0.
The baseline includes the extensive pending Worldstream work present on
entry. This slice changes only the explorer-readiness condition in
`tools/bench_fresh_sync.c`, extends the pending outcome selftest, and adds
this report. Earlier staged work is byte-for-byte unchanged.

After an initial tip observation, the benchmark continued fetching the
explorer page on every poll even when the node resumed synchronization or
the state RPC stopped responding. Each unnecessary request launches curl,
can download a page, and can consume its two-second HTTP budget. Readiness
is now probed only on a current `at_tip` observation, until first success.
The first-tip milestone, consecutive-tip grace, deadline, and explorer
success requirement remain unchanged. Explorer readiness remains a first
observation, not a continuous availability guarantee.

The regression compiles the production poll loop and result path with a
deterministic clock and mocked RPC/explorer responses. No node, network,
wallet, credentials, or production datadir participates. Its 30-second
budget starts with a tip observation at elapsed second 10:

| Fixture | Before | After |
|---|---|---|
| Tip, then permanently syncing; explorer unavailable | 11 explorer requests, failure | 1 request, failure |
| Tip, then state RPC failures; explorer unavailable | 11 requests, failure | 1 request, failure |
| Tip, syncing gap, recovery on poll four; explorer ready during gap | Explorer observed at 12 s; completes at 22 s | Explorer observed at 16 s; completes at 22 s |
| Tip, missing RPC gap, recovery on poll four; explorer ready during gap | Explorer observed at 12 s; completes at 22 s | Explorer observed at 16 s; completes at 22 s |
| Continuously at tip, explorer ready on poll four | 4 requests; completes at 16 s | Same |

Both permanent-loss fixtures retain 11 state polls and terminate at elapsed
second 32, after crossing the unchanged outer deadline. Existing cases also
assert zero explorer requests before the first tip and continued retries
while at tip. These are deterministic observer-demand measurements, not
measured end-to-end IBD or GUI speedups. The mocked requests consume no
clock time; no wall-time saving is claimed.

Reproduce with:

```bash
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze
# The final positional argument can select a saved baseline C source.
```

The saved working-tree baseline C SHA-256 is
`06435f68965bc282ccd373a8bd9fb32d5a9166fb2b4812e670f3774bab82ec37`.
The resulting C SHA-256 is
`d4dd0d5bc709f9115932493740374609043d82848fd33ea4ccfc4976dceb7e20`.
The new cases fail on the baseline request budgets and observation timing;
all 24 cases pass after the change with C23 warnings-as-errors and GCC
static analysis. The existing pending Makefile target already invokes this
selftest, so no additional build-target change belongs to this slice.

Surrounding phase-log, complete-log, startup, command-output, HTTP-deadline,
page-size, readiness, and height-demand selftests pass. The existing timing
selftest fails identically before and after: expected completion at 21 s,
actual 19 s. That assertion remains unchanged. Full-tool builds succeed for
both versions with the same seven existing warnings about ignored `system`
results and potentially truncated copy commands. Focused strict compilation
and analysis cover the modified polling loop.

Bash syntax, architecture-tree, pipefail-status, discarded-status,
shell-host-assumption, consensus-parity (including its selftest), and
core-seal-root-mirror checks pass. Direct seal verification matches all 554
files and 80 sections. The outcome script is still untracked from earlier
work and therefore outside index-based shell lint; it was parsed and run
directly. ShellCheck is unavailable. `make -j4 lint-fast` exceeded a
55-second bound during setup, so no aggregate lint pass is claimed.
The exact slice diff was reviewed and `git diff --check` passes.

Consensus, independent validation, optional acceleration policy, and all
Hetzner-owned scheduling/database/runtime surfaces are unchanged. No secrets,
generated files, binaries, logs, caches, or datadirs belong to the slice.
Temporary baselines, fixture output, and build products remain under
`/tmp/worldstream-explorer-demand/`.

Publication is incomplete: repeated fetch attempts cannot write the read-only
`.git/FETCH_HEAD`, and querying origin's development branch fails DNS
resolution. No upstream integration, commit, push, or remote-SHA equality
is claimed. The branch remains unchanged. Publication also requires resolving
the existing timing-test failure and completing the required lint gate.
