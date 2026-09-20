<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream peer-observation cost

The shared peer counter used by the lane-health and SLO observers started
three text tools per observation: `grep`, `wc`, and `tr`. Under `pipefail`,
an empty peer list printed `0` but returned status 1, contrary to the reader's
documented successful-zero contract. A fixture reproduces both problems.

The counter now uses one awk pass, preserving the existing line-local
`"addr"` key count, including multiple matches per line. It returns a
successful zero for no matches. RPC success and missing-observation decisions
remain with the callers; an upstream command failure still propagates through
`pipefail`. This is a text counter, not a new JSON validator.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with the pre-existing Worldstream
working changes preserved. Baseline library SHA-256:
`01602094c2f8ea3f73101bfc8974333856f7bf2d3f7a52802443d002c7044e17`.
Updated library SHA-256:
`d5b7aac4bd7bceb725eaf906a5001ac249d0bc5a98862b3a6e72b61757276475`.

On Linux x86_64, AMD EPYC 7402P, Bash 5.2.21, three runs of 300 observations
of the same 64-peer response produced these measurements:

| Measurement | Before | After |
|---|---:|---:|
| External text tools per observation | 3 | 1 |
| Median user + system CPU, seconds | 2.089 | 1.050 |
| Median wall time, seconds | 0.886 | 1.016 |
| Wall time range, seconds | 0.846–0.903 | 0.921–1.046 |

The result supports lower observer CPU cost, not a wall-time speedup. The
baseline pipeline runs its processes concurrently. Measurements used warm
ordinary filesystem caches and shared host resources; other checks were
running during the candidate samples. Timing is informational, while the
process budget and exact output/status assertions are deterministic. No
end-to-end IBD or time-to-tip improvement is claimed.

Reproduce without a node, datadir, wallet, or network:

```sh
bash tools/scripts/evidence_peer_count_selftest.sh --bench
make evidence-selftest
```

An optional final argument selects a saved baseline library. The baseline
fails four zero-result status checks and the process budget. The candidate
passes ten byte/status cases, including an 8,192-peer line, and preserves a
failed upstream producer's status. Both mawk and gawk pass. A mutation that
doubles the count fails six cases. The test also passes with the committed
library plus only the new counter definition, independent of the earlier
string and systemd-reader edits.

The evidence and tip-agreement Make suites pass. The node SLO probe, hold
judge, and pager shell selftests pass. Shell syntax, shell-host assumptions,
architecture, no-API-keys, no-Python and whitespace checks pass. The core seal
verifies all 554 files and 80 sections, and the core-root mirror matches.
ShellCheck is unavailable. The registered SLO test prerequisite did not
complete: its attempted build encountered unavailable dependency downloads,
read-only submodule metadata, and source-identity supersession during the
initial edit. No registered C test or full node build is claimed.

The completed `make lint-fast` run has four existing checkout/environment
failures: injected `.agents`/`.codex` root entries, fresh-sync benchmark
complexity above its pin, 18 stale flag first-use pointers, and a Windows
fixture scratch path outside the writable roots. No assertion or threshold
was weakened.

This slice consists only of the peer-counter hunk, its standalone selftest,
one additional invocation in `evidence-selftest`, and this note. Earlier
changes and the staged index remain intact. Consensus, validation, optional
acceleration, runtime scheduling, and database behavior are unchanged. No
generated artifacts, binaries, logs, or temporary benchmark output belong to
the slice.

Publication remains incomplete: Git metadata is read-only, and the origin
query cannot resolve GitHub. No commit, push, upstream integration, or exact
remote-SHA verification was possible. The branch remains unchanged.
