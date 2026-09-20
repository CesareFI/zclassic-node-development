<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: jump to the profile field delimiter

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold profiler already skipped delimiter-free 128-byte spans, but inspected
the final span one character at a time. Indented, unavailable counters made
each retry repeat this work. The reader now locates the final quote or comma
within that span with an anchored match, then applies its existing boundary
decision. First integer selection, exact integer text, missing-value defaults,
duplicate handling and input draining are unchanged.

This slice changes only that loop, registers its new regression in the existing
`fold-profile-selftest` target, and adds this record. The sampler and Makefile
already contained substantial unfinished work. The entry sampler SHA-256 is
`d584d4158cd902ea7a58ffa39e9bd38bffc9ce53f7bd2356b8d466664211c14c`.
Measurements compare against those entry bytes, not pristine HEAD. Snapshots,
logs and the isolated delta are temporary files under
`/tmp/worldstream-boundary-jump/`; they are not publication artifacts.

## Measurement

Linux x86_64, GNU awk 5.2.1, warm shell/tool caches, synthetic responses with
96 spaces before each unavailable counter and a final usable wide integer.
No node, peer, network, credentials or datadir participates. Ambient host load
is uncontrolled; some runs overlapped bounded lint or fixture checks. Three
repetitions execute baseline then candidate. Each wall-time result covers 100
uninstrumented reader invocations, including shell and awk startup.

| Fixture | Baseline | Candidate |
|---|---:|---:|
| 12 unavailable counters, boundary probes | 1,165 | 25 |
| 1,000 unavailable counters, boundary probes | 97,001 | 2,001 |
| 12 counters, wall seconds | 0.53 / 0.54 / 0.53 | 0.45 / 0.45 / 0.45 |
| 1,000 counters, wall seconds | 6.06 / 6.10 / 6.15 | 1.00 / 1.01 / 1.01 |

Stress-fixture median wall cost fell about 83%. This establishes a bounded
observer improvement, not faster real IBD or time to tip. Compact responses
with an adjacent delimiter retain the existing immediate check.

## Validation and remaining gates

The new regression checks both nearest-delimiter outcomes at every padding
length from 0 through 257, exact wide integers, and a deterministic probe
budget. The entry implementation fails that budget with 1,165 probes; the
candidate passes with 25. GNU awk, mawk and BusyBox awk pass.

Reproduction commands:

```sh
sh tools/scripts/fold_profile_boundary_jump_selftest.sh --bench
make fold-profile-selftest fold-profile-summary-selftest
```

Both aggregate targets pass, including exact CSV, refusal/recovery, actual RPC
deadlines, bounded scans and long-history summaries. Existing boundary and
retry regressions also pass. POSIX shell and Bash syntax, direct architecture,
shell-host-assumption, pipefail-status and discarded-status checks pass.
`git diff --check` passes. `make lint-fast` exceeded its 50-second bound during
initialization; no aggregate lint pass is claimed. ShellCheck and the public
node binary are unavailable. No C source changed; no compiler or live-chain
acceptance is claimed.

Consensus, cryptographic validation, optional acceleration policy and
Hetzner-owned code are untouched. The isolated delta contains no credentials,
logs, caches, binaries or generated output. Previous dirty work is preserved.

Publication remains incomplete. Fetch fails because `.git/FETCH_HEAD` is
read-only; an origin branch lookup fails because GitHub cannot resolve.
Staging the new regression succeeded, but restoring its unstaged status failed
because `.git/index.lock` cannot be created. It remains staged; do not commit
the full existing index or the whole dirty sampler/Makefile as this slice.
No commit, push, upstream integration or exact remote-SHA match is claimed.
Aggregate lint and the inherited uncommitted prerequisites also remain to be
resolved before this delta can be published coherently.
