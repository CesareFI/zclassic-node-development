<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stop polling completed onion RPC milestones

Scope: the isolated bootstrap observer in `tools/scripts/onion_pair_watch.sh`.
Its four RPC-derived flags already latch for the probe's lifetime. Once all
four were true, each subsequent observation still called `onionstatus` and
launched five JSON readers, without changing any milestone. This can occur
while waiting for service-side log evidence or peer connectivity.

The observer now skips that RPC only after all four flags are true. A single
missing flag retains the existing query and parsing behavior. Missing log
milestones and the separate `getconnectioncount` checks continue. No readiness
threshold, validation predicate, acceleration policy, or node behavior changes.
Consensus and Hetzner-owned scheduling, database and runtime code are untouched.

## Baseline and measurement

Branch: `agent/worldstream-ibd-20260918`. HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.
The baseline is the working observer at entry, SHA-256
`384fa066866c8a99fac1decdd6860815376d973c0fc9f1c7bd2b0bc6ebfeda12`.
Earlier staged log-milestone changes remain prerequisites, not changes authored
in this slice. The original file and an incremental slice patch are preserved
under `/tmp/worldstream-onion-rpc/`; neither belongs in a commit.

Host: Linux 6.8.0-139-generic, x86_64, AMD EPYC 7402P, 48 logical CPUs,
Bash 5.2.21. Synthetic local fixtures, warm tools/filesystem caches, no node,
network, chain data or production datadir. The RPC stub returns a small JSON
response; a counting wrapper executes the real in-tree `jsonq` for each query.
That helper was compiled with GCC 14.2, C23, `-O2 -Wall -Wextra -Werror
-pedantic`, using the same bytes for baseline and candidate runs.

Three repetitions ran baseline then candidate sequentially under uncontrolled
ambient load, overlapping a bounded lint attempt. Each timed 100 polls after
the RPC milestones had completed; setup and fixture compilation are excluded.

| Measurement | Baseline | Candidate |
|---|---:|---:|
| `onionstatus` calls per completed poll | 1 | 0 |
| JSON reader processes per completed poll | 5 | 0 |
| 100 polls, wall seconds | 2.974 / 2.988 / 2.980 | 0.013 / 0.013 / 0.013 |

These measurements establish observer overhead only. They do not establish
end-to-end IBD speed, live RPC latency savings or time-to-tip improvement.
Partially completed RPC milestones still incur five readers per observation.

## Regression and validation

With `jsonq` built, reproduce with:

```sh
ZCL_JSONQ=build/bin/jsonq bash tools/scripts/onion_pair_rpc_selftest.sh --bench
ZCL_JSONQ=build/bin/jsonq bash tools/scripts/onion_pair_watch.sh --selftest
```

The new regression optionally takes a probe script as its final argument for
baseline comparisons. The baseline passes value/continuation checks, reports
one RPC and five readers per completed poll, then fails the zero-work budget.
The candidate passes. The enclosing probe self-test invokes this regression.

Coverage includes no cookie, empty/malformed/missing responses, zero counters,
each individually missing RPC milestone, completed log milestones with pending
RPC evidence, incomplete byte counters, incoming byte evidence, and delayed
service/log milestones after RPC completion. Existing log-observer tests pass
26 cases. The broader probe self-test passes its verdict, port allocation and
ledger checks. Its connectivity requirement remains intact.

Passed: Bash syntax, discarded-status, pipefail-status, shell-host-assumption,
architecture-tree checks and `git diff --check`. The new untracked regression
was explicitly included in shell checks. A single-file pipefail invocation
first reported unrelated baseline rows stale because its scan excluded their
files; rerunning with the complete tracked shell set plus the new file passed.
No lint baseline was changed. ShellCheck is unavailable. `make lint-fast`
exceeded a 55-second bound during preparation after warning about missing Tor
archives; no aggregate lint pass is claimed. No compiled implementation changed.

## Publication status

The slice consists of the RPC guard and self-test invocation added to the
already-dirty observer, the new regression, and this note. The exact incremental
diff was inspected; it contains no secrets, generated artifacts, logs, caches,
binaries or datadirs. Unrelated pending work is preserved. Do not commit the
entire dirty checkout or assume the full observer diff belongs to this slice.

Publication remains incomplete. Fetch cannot write `.git/FETCH_HEAD` because
Git metadata is read-only, and GitHub remote lookup fails DNS resolution.
No commit, push or exact remote-SHA verification is claimed. Aggregate lint
also remains outstanding. A supervisor with writable Git metadata and network
access must finish integration and required gates before publishing only the
development branch.
