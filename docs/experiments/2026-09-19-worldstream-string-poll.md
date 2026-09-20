<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: compact string observation cost

Scope: shared shell instrumentation used by `node_slo_probe.sh` for onion
address and blocker identifiers during synchronization monitoring. This slice
changes no node code, consensus rule, validation, scheduling, database, or
acceleration setting. It makes no end-to-end IBD or time-to-tip claim.

The checkout started at `c1f7863d098e1efaa8deba240c580ae0559312a5` with
extensive pre-existing Worldstream edits. The pre-session string reader
launched sed for each field. The committed parent additionally piped through
head. A compact observer should not need either process.

The change adds an in-shell regex path for strings of at most 4096 characters
on one line with an identifier key. It preserves the last valid match on that
line, empty values, and the reader's existing escaped-quote behavior. Longer
input, multiline input, and non-identifier keys use the existing fallback.
This is an identifier reader, not a new general JSON decoder.

## Offline measurement

Linux x86_64, Bash 5.2.21, `LC_ALL=C`, warm synthetic response:
`{"height":3200000,"stage":"header_admit","ready":false}`.
Each measurement calls the actual reader 2000 times; no node, socket, or
production datadir is involved. Wall times are descriptive, not pass limits.

| Source | Three wall times (seconds) |
| --- | --- |
| Pre-session working library | 5.265, 5.350, 5.370 |
| Changed working library | 0.141, 0.141, 0.141 |
| Committed parent library | 5.810, 6.147, 6.160 |
| Parent plus this slice alone | 0.143, 0.143, 0.142 |

The deterministic regression counts sed calls: 100 compact observations
previously launched sed 100 times; now they launch it zero times. The parent
also launched head. Baselines pass value checks and fail the process budget;
both candidate variants pass. The fixture also checks missing/wrong-type
fields, duplicates, empty strings, whitespace, literal backslashes, existing
escape handling, repeated lines, regex keys, and both sides of the size limit.

Reproduce with:

```bash
bash tools/scripts/evidence_string_poll_selftest.sh --bench
bash tools/scripts/evidence_string_poll_selftest.sh --bench /path/to/baseline-library.sh
make evidence-selftest
```

The benchmark regression is registered under `evidence-selftest`. In the
pre-existing working-tree aggregate regression, the expected compact
three-field parser count is adjusted from two to one. That local adjustment
belongs with the already-pending aggregate test; it is not needed by the
standalone slice against the committed parent.

## Validation and limits

The focused regression and Bash syntax checks pass against the working library
and independently against the parent plus just this insertion. The broader
evidence readers, intervention ledger, intervention wrapper, public explorer,
and SLO monitor selftests pass on isolated fixtures. `git diff --check` passes.
Shell lint passes for pipefail status pipelines, discarded statuses, host
assumptions, and the no-Python contract.

The 32-gate lint-fast driver was also exercised. The dirty primary checkout
has unrelated root-file, complexity, and flag-reference failures. The isolated
parent-plus-slice tree passes 31 gates; the remaining Windows guard initially
cannot create its default scratch directory under the restricted home path.
Rerunning that guard with its documented
`ZCL_WINDOWS_ACCEPTANCE_GUARD_SCRATCH=/tmp` override passes its 7/7 selftests
and its 41-file production scan, completing all 32 checks for the isolated slice.
No assertion, baseline, or validation threshold was weakened.

No compiler check is needed for this shell-only change. The candidate contains
only source, its regression registration, the regression, and this report;
no secrets, logs, binaries, caches, or benchmark artifacts are included.

Remaining uncertainty: the fixture measures observer cost, not a real IBD
speedup. A future consenting isolated sync run must measure how often these
fields are read and their contribution to total time-to-tip.
