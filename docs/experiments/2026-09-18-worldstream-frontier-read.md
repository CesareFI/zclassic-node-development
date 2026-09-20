<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream frontier observation retries

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, Linux x86_64,
Bash 5.2.21. Both measured `rpc_frontier` functions matched that commit at
entry, although their containing files already had unrelated dirty changes.
No node, network peer, wallet or production datadir was used.

Both cold-start and disruption-recovery stopwatch readers tested captured RPC
output with `printf | grep -q` under `pipefail`. When an early match closes
the pipe before printf finishes writing, SIGPIPE makes a valid frontier look
absent. A valid JSON fixture containing `hstar` followed by a newline and a
1 MiB padding string reproduced this in both actual reader functions.

| Per observation, large early match | Before | After |
|---|---:|---:|
| RPC attempts | 6 | 1 |
| Scheduled backoff | 12 seconds | 0 seconds |

The test substitutes a counter for sleep; the 12 seconds is the exact sum of
the requested delays, not measured wall time. When only the first RPC succeeds
and later attempts are empty, the old reader also discards that valid sample.
The fix uses a Bash literal substring predicate, preserving the old detector's
meaning while removing the pipe. Busy and empty responses still make six
attempts with the same 1,1,2,3,5-second delays. Each harness retains its own
existing policy for busy partials followed by empty responses.

An informational benchmark of 100 small successful fixture reads measured
0.665 to 0.219 seconds for cold-start and 0.650 to 0.240 seconds for recovery.
These warm local measurements include fixture counter file I/O and shell
substitutions. They are observer costs, not chain synchronization measurements.
No production frequency or end-to-end IBD improvement is claimed.

Reproduce the 16 cases and optional timing with:

```bash
bash tools/scripts/stopwatch_frontier_read_selftest.sh --bench
baseline=$(mktemp -d /tmp/z23-frontier-baseline.XXXXXX)
for script in cold_start_to_tip_stopwatch.sh network_disruption_recovery_stopwatch.sh; do
    git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/$script > "$baseline/$script"
done
bash tools/scripts/stopwatch_frontier_read_selftest.sh --bench "$baseline"
```

The baseline must fail the four large early-match cases. The regression
extracts the actual reader functions without executing harness setup, checks
exact response bytes, call counts, backoff and busy classification, and is
included in both harness selftests. It covers small, large early/late match,
transient success, busy, busy-then-empty, similar-key and empty responses.
The pipefail lint allowance decreases by one site for each harness.

Both full harness selftests, the recovery timing regression's six scenarios,
artifact-symmetry mutation tests, shell syntax, pipefail-status,
discarded-status, shell-host-assumptions and architecture checks pass.
`git diff --check` passes. ShellCheck is unavailable. `make lint-fast`
reports four existing failures: stray root entries, complexity in
`tools/bench_fresh_sync.c`, stale flag source-line pointers, and a Windows
guard fixture trying to write outside the sandbox. This slice does not shift
existing source-line pointers. The public binary build is blocked by missing
vendored dependencies, unavailable GitHub DNS and read-only Git metadata.

Only harness observation, its regression and its lint debt counts change.
Consensus, cryptographic validation, acceleration policy, peer/request
scheduling, database tuning and node runtime code are untouched. Existing
dirty work is preserved; no secrets or generated artifacts belong to this
slice. Publication is blocked by read-only `.git` and unavailable GitHub DNS;
no commit, push or verified remote SHA is claimed.
