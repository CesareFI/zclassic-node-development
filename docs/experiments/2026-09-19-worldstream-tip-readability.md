<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: remove recovery readability polling subprocesses

Branch: `agent/worldstream-ibd-20260918`; base HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The sync-recovery stopwatch launched a command substitution and printf/grep
pipeline at preflight and on every recovery sample solely to test whether
`network_tip_read_ok` matched true. The observer now uses a Bash predicate.
The existing line-local whitespace, duplicate-key presence and true-prefix
semantics are preserved. This is a reader of the existing telemetry shape,
not a general JSON parser or a change to recovery acceptance.

## Baseline and measurement

The working script at entry had SHA-256
`6ad56db82f5c8d34cd395881e7aa817497275eef51250ba61ae40677bd862b11`.
It includes earlier uncommitted work that this slice does not own.
The local baseline and isolated working-tree and HEAD-relative patches are in
`/tmp/worldstream-tip-readability/`. They are temporary development evidence.

Linux x86_64, Bash 5.2.21, C locale, warm tools, synthetic compact frontier
response, uncontrolled ambient host load. Three sequential baseline repetitions
preceded three candidate repetitions; each performed 1,000 observations.
No node, RPC, datadir or network participated in these measurements.

| Observation cost | Baseline | Candidate |
|---|---:|---:|
| Wall seconds, three repetitions | 4.096 / 4.054 / 4.046 | 0.050 / 0.046 / 0.045 |
| External grep calls per 100 observations | 100 | 0 |

Median observer time fell about 99%. This is not an end-to-end IBD or
time-to-tip improvement claim; a real sync benchmark remains necessary.

## Validation

```sh
bash tools/scripts/netdisrupt_tip_readability_selftest.sh --bench
bash tools/scripts/network_disruption_recovery_stopwatch.sh --selftest
bash tools/scripts/netdisrupt_stopwatch_timing_selftest.sh
bash tools/scripts/stopwatch_busy_selftest.sh
bash tools/scripts/stopwatch_json_selftest.sh
```

The new regression passes 15 classification cases, both production call-site
expressions, large responses, the zero-external-tool budget, and operation
without PATH tools. The baseline passes the classification cases and fails
the process budget with 100 grep calls. The new regression also passes against
the slice applied to pristine HEAD, independently of earlier working-tree
changes. The complete harness `--selftest` also passes in an isolated copy
with the pristine HEAD library and this slice. The new regression is invoked
by that existing selftest entry point.

Broader checks against the working tree pass: frontier-read cases, six
deterministic recovery timing scenarios, 13 busy-classification cases and 15
JSON-helper checks. The timing scenarios use only their own disposable `/tmp`
process fixture. Bash syntax, architecture-tree, discarded-status,
pipefail-status and shell-host-assumption gates pass. `git diff --check` passes.
No C source changed; compiler checks are not applicable. ShellCheck and the
public node binary are absent. `make lint-fast` exceeded a 180-second bound
during initialization; no aggregate lint pass is claimed.

Consensus, cryptographic validation, optional acceleration policy, and
Hetzner-owned scheduling, database and runtime code are unchanged. The exact
slice contains only the observer change, its regression and this report; no
secrets, logs, generated output, binaries or datadirs are included.

Publication is incomplete. Fetch failed because `.git/FETCH_HEAD` is read-only;
applying the isolated patch to the index failed because `.git/index.lock`
could not be created on the read-only filesystem. Remote branch lookup also
failed to resolve GitHub. No commit, push or remote-SHA verification is claimed.
The harness contains unrelated earlier changes: do not stage its whole working
copy as this slice. The HEAD-relative patch isolates the intended change.
