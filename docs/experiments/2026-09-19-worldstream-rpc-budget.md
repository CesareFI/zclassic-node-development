<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound the time-to-tip probe's RPC observation

The cold-start time-to-tip probe checked its deadline after an unbounded
`getblockchaininfo` call. A stalled client therefore delayed the benchmark's
timeout report indefinitely. This is an observer bottleneck, not evidence of
slow chain validation.

`read_tip_sample` now checks the remaining budget before dispatch, passes that
allowance to `timeout`, and gives a TERM-resistant client one second before
forced termination. Failed or timed-out output is discarded. The post-RPC
timestamp and existing tip acceptance predicates remain in place. An expired
budget dispatches no RPC and clears any previous response.

## Local fixture evidence

Measured on Linux x86_64, Bash 5.2.21, GNU timeout 9.4. No node, chain fixture,
peer, wallet, or production datadir was used. The fixture RPC waits four
seconds before returning a tip-shaped response; a second mode ignores TERM.

| RPC mode | Remaining budget | Before | After |
| --- | ---: | ---: | ---: |
| Stalled | 2 s | 4 s | 2 s |
| Ignores TERM | 2 s | 4 s | 3 s |

These are single-run, whole-second fixture observations, not IBD speedup
claims. The regression uses a virtual stopwatch clock with eight seconds
already consumed from a ten-second budget. It delegates to the real timeout
and RPC processes, checks the exact remaining allowance and kill grace, and
asserts that canceled output cannot become a usable sample. Wall time is
printed, never used as a pass threshold. It also covers an already-expired
budget, successful output, and failed commands emitting plausible heights.

Run:

```sh
bash tools/scripts/cold_start_rpc_budget_selftest.sh
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
bash tools/scripts/cold_start_snapshot_metadata_selftest.sh
```

The regression fails against the pre-change observer and passes after the
change. The aggregate probe self-test, snapshot metadata tests, shell syntax,
and `git diff --check` passed. No C code or consensus file changed. Optional
bootstrap behavior, independent validation, and Hetzner-owned scheduling and
database behavior are untouched. This bounds the RPC wait only; existing
poll sleeps, seed-log observation, and other harness stages have their own
costs.

The discarded-status and no-wallclock-assertion static gates passed. ShellCheck
is not installed. `make lint` was attempted but interrupted after several
minutes without further visible progress following template generation; it
also reported absent Tor archives. Full lint is incomplete, not a passing
publication gate.

## Source and publication status

Branch: `agent/worldstream-ibd-20260918`, base HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The checkout already contained many
staged, unstaged, and untracked Worldstream changes. The pre-change probe SHA256
was `ab920b87baedc0e7f1579476b57c77bfe56b33b399fd28fb301822c4380b9764`;
the changed probe SHA256 is
`fe757f5d08f6d68e27091ae835b85b0d08fe5f6f6b09161ef12350c8d143e5aa`.
Existing edits were preserved; this slice must not commit that unrelated work.

Publication is unavailable in this session: `.git` is read-only (fetch cannot
write `FETCH_HEAD`), and a read-only origin query fails to resolve GitHub.
No commit or push is claimed, and current upstream identity is unverified.
