<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound catch-up benchmark RPC observations

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, Linux x86_64,
Bash 5.2.21, GNU coreutils timeout 9.4, GCC 14.2.0. The experiment uses
local shell RPC doubles and the actual JSON reader, with no sockets, node,
production datadir, or wallet. An isolated checkout excludes the extensive
pre-existing staged and unstaged Worldstream work.

The two-node peer-tip benchmark checks its absolute deadline between RPCs,
but previously did not cancel an outstanding observation. A stalled RPC could
therefore delay reporting benchmark failure beyond the catch-up budget. The
POSIX RPC client's default 30-second curl allowance is independent of that
budget, and callers can override it to a longer duration.

The regression supplies a deterministic clock with two seconds remaining and
an RPC double that emits a plausible response, then sleeps eight seconds.
An outer five-second watchdog contains the baseline. Watchdog cancellation
is a failure, never a passing benchmark observation. Recorded elapsed seconds
are diagnostic; assertions check return status, exact requested allowances,
and whether an expired read launches a client.

| Observation | Baseline | Changed harness |
|---|---|---|
| Stalled readiness read | Watchdog exit 124 at 5 s | Failure exit 1 at 2 s |
| Stalled height read | Watchdog exit 124 at 5 s | Failure exit 1 at 2 s |
| Stalled hash read | Watchdog exit 124 at 5 s | Failure exit 1 at 1 s after the height consumes one clock second |
| Readiness client ignores TERM | Watchdog exit 124 at 5 s | Failure exit 1 at 3 s, including forced-kill grace |
| Failed RPC with plausible output | Refused | Refused |
| Successful readiness and exact-tip reads | Accepted | Accepted |

Pollers now scope their absolute deadline through `tn_result`, which computes
the remaining allowance separately before each height or hash query. Expired
reads do not launch a client. GNU-compatible `timeout --kill-after=1` bounds
the remaining wait, including a one-second termination grace. Timed-out or
failed command output remains inadmissible, and the original post-read
strict deadline and exact-hash checks remain. Pollers avoid sleeping after an
RPC has consumed the deadline. Hosts without `timeout` get an explicit
preflight refusal before any node starts; native macOS/Windows execution was
not measured here.

Reproduce with the normal JSON-query helper built:

```sh
make jsonq
bash tools/scripts/two_node_peer_tip_selftest.sh
bash tools/scripts/two_node_peer_tip_deadline_selftest.sh
```

The latter also accepts the harness path in another checkout for comparison.
The new regression is invoked by the existing peer-tip selftest, already part
of `check-shell-host-assumptions`. The flag registry's first-use line for
`ZCL_PEER_TIP_TMP` was refreshed; its behavior is unchanged.

Validation: seven RPC scenarios plus expired-dispatch refusal pass; the
existing typed-RPC, malformed/error response, exact-hash, shared-deadline,
late-answer and cleanup-containment cases pass. Port-probe, isolated-readiness,
and service-argument selftests pass. Shell syntax, discarded-status,
pipefail-status-pipe, shell-host-assumptions, flag registry, architecture,
consensus-parity and `git diff --check` pass. All 32 `LINT_FAST_GATES` pass
through the canonical lint driver: the initial run passed 29, then the three
remaining gates passed after building their missing helper binaries and using
the existing Windows-guard scratch override inside the writable fixture.
No gate or threshold was weakened. GCC built the unchanged JSON and lint
helpers with the repository's C23 warning/error flags; ShellCheck and Clang
were unavailable. Core seal verification confirms all 554 files and 80
sections unchanged.

This establishes bounded benchmark observation latency, not reduced real-chain
IBD time. No consensus predicates, validation, optional acceleration behavior,
node runtime, peer scheduling, stalled-request recovery, or database tuning
changed. Full node/chain acceptance was not run; fetching missing vendor inputs
failed on GitHub DNS resolution. Only source, the regression, the flag-reference
correction and this record belong to the slice; fixture output and binaries
remain outside the commit.
