<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound fold-profile telemetry clients

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold profiler made five sequential telemetry requests without a harness
timeout. A client that emitted a plausible response and then stalled prevented
the sampler from observing later intervals or reaching its summary. Each RPC
now receives a five-second budget and a one-second TERM grace period before
KILL. Nonzero completion rejects the entire sample through the existing refusal
path. The harness requires `timeout` or `gtimeout` before launching a copy.

This slice changes only that observer, its Makefile test registration, and a
local mock regression. Existing staged, unstaged and untracked work is retained.
The working-file baseline, rather than pristine HEAD, is SHA-256
`013bc68d4d236fca7f202cc9ce51a45264e828eb54c2137e4b4e2b273587d769`
for `tools/scripts/fold_profile.sh`. Entry snapshots and the isolated patch are
under `/tmp/worldstream-fold-rpc/`; temporary output is not repository content.

## Measurement and regression

Linux x86_64, GNU coreutils timeout 9.4, local shell mock, ordinary warm tool and
filesystem caches. No node, chain, network or production datadir participates.
The mock emits nonempty telemetry and then sleeps for 30 seconds.

| Case | Baseline | Candidate |
|---|---|---|
| First RPC stalls | Test guard aborts after 8 seconds, rc 124 | Rejected after about 5 seconds |
| Each of the five endpoints stalls | First failure prevents baseline suite completion | All five reject in 5–6 seconds |
| Client ignores TERM | No harness deadline | Killed after about 6 seconds |

Times have one-second resolution. Every candidate case preserves the previous
CSV bytes, skips subsequent RPCs, and successfully records a later healthy
sample. This bounds a stalled observation; it is not an end-to-end IBD speedup
or proof of a hard real-time deadline under arbitrary host load. A sample with
five near-deadline successful calls can still consume about 25 seconds.

## Validation

- Baseline fails `sh tools/scripts/fold_profile_rpc_deadline_selftest.sh
  /tmp/worldstream-fold-rpc/fold_profile.before.sh` at the outer guard.
- `make fold-profile-selftest fold-profile-summary-selftest` passes, including
  the new deadline cases, 35 existing RPC refusal cases, exact CSV and parser
  work checks, and summaries under GNU awk, mawk and BusyBox awk.
- POSIX shell and Bash syntax, architecture-tree, shell-host-assumptions,
  pipefail-status-pipe, discarded-status and `git diff --check` pass.
- `make lint-fast` did not complete within a 50-second bound during build
  initialization. No aggregate lint pass is claimed. No C source changed;
  compiler and live-chain validation were not applicable to this shell slice.

The exact slice diff was reviewed. Consensus, cryptographic checks, optional
acceleration policy, and Hetzner-owned scheduling, database and runtime code
are unchanged. No secrets, generated files, binaries or benchmark output are
part of the slice.

Publication remains incomplete: `.git/FETCH_HEAD` is read-only and GitHub
cannot resolve from this environment. No commit, push or remote-SHA agreement
is claimed. The branch remains unchanged. Do not stage the entire dirty
Makefile or profiler as this slice; both contain substantial earlier work.
