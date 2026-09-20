<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fresh-sync observation timestamps

The standalone fresh-sync benchmark reused the poll-entry clock for RPC tip,
log phases, explorer readiness and completion. Observer latency was therefore
subtracted from reported time-to-tip and startup time. This slice corrects
measurement accuracy; it does not demonstrate faster chain synchronization.

The deterministic regression runs the actual polling loop with a fake
monotonic clock. Relative to benchmark start, the first poll begins at 10 s;
the state RPC takes 1 s, the height RPC 2 s, the log observation 1 s, and the
explorer observation 2 s. No node or network participates.

| Observation | Baseline report | Corrected report |
|---|---:|---:|
| First observed tip | 10 s | 11 s |
| First observed log phases | 10 s | 14 s |
| First successful explorer response | 10 s | 16 s |
| Completion after the existing tip grace period | 18 s | 21 s |

The benchmark now samples the clock immediately after the state RPC, after
the log observation, after successful explorer readiness, and before the
completion decision. The state timestamp is retained across the later height
and log probes. First-observation semantics and the greater-than-five-second
tip grace condition remain intact. Failed observations do not set milestones.

These are observer completion times, not reconstructed node event times.
Startup cookie waiting and polling granularity can still delay detection.
The existing outer timeout remains checked between polls; this change does
not introduce a strict whole-benchmark deadline. Optional bootstrap readiness
and independent chain validation remain separate measurements.

Baseline branch: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including existing pending
Worldstream changes. Baseline `tools/bench_fresh_sync.c` SHA-256:
`e26f236faf2d3afba4240850e83cf6f7f53b92ebbfe4a7630fb73e829c1118a7`.
Updated SHA-256:
`8d0de6679751468115ade036049be7dd0b9ba9d26be5efce4b465d91c0472000`.
The slice owns only these timestamp changes, the new timing selftest, its one
Makefile invocation and this note. The test uses the pending phase-observer
state already present in the checkout; it is not independent of that source.

Reproduce with:

```bash
bash tools/scripts/bench_fresh_sync_timing_selftest.sh --analyze
make bench-fresh-sync-selftest
```

An optional source path selects a saved baseline. The baseline fails the
timestamp assertions. On Linux x86_64 with GCC 14.2, the corrected fixture
passes normal observations, a missing first state RPC, and a failed first
explorer probe. Reverting each of the four timestamp fixes individually makes
the regression fail. The extracted production loop and parsers pass C23
`-Wall -Wextra -Werror` and GCC `-fanalyzer`.

The existing phase-log, command-output and HTTP-deadline regressions pass
directly, as do the stopwatch judge and artifact-symmetry suites. The complete
benchmark builds with its shipped compiler flags.
Strict compilation of the complete tool still fails on the same seven
baseline diagnostics: five ignored `system` results and two potentially
truncated certificate-copy commands. No warning policy was changed.

Architecture, shell syntax, shell-host assumptions, discarded-status,
pipefail-status, no-wallclock-assertion, no-API-keys, no-Python and whitespace
checks pass. All 554
sealed core files and 80 sections verify, and the exported root mirror matches.
Consensus, independent validation, optional acceleration, peer scheduling,
database tuning and node runtime behavior are unchanged. No secrets, binaries,
datadirs, logs or temporary benchmark output belong to this slice. The existing
staged diff is unchanged.

The Make selftest and `make lint-fast` each exceeded a 50-second bound during
setup before reaching their test/gate recipes; neither aggregate is claimed
green. Publication is incomplete: Git metadata is read-only, `origin/main`
is unavailable locally, and querying origin fails on GitHub DNS. No commit,
push, upstream integration or remote-SHA equality is claimed.
