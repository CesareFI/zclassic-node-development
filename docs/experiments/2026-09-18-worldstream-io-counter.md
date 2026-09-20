<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream stopwatch disk-counter observation

The cold-start stopwatch starts two awk processes on every process-counter
sample to extract read_bytes and write_bytes from an already-read /proc/io
record. The reader now uses Bash builtins, eliminating those parser processes.
It preserves the first valid matching field, exact decimal text (including
wide values and leading zeros), and -1 for absent or malformed observations.
It still measures block-layer counters, not page-cache I/O.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with existing pending Worldstream
changes. Baseline stopwatch SHA-256:
`f631d5a9de3ee8a88078d2c998c84014bd9562b1414b60dc760e7e53040906a7`.
Updated stopwatch SHA-256:
`059a2419f7298c9df2aa85bfa0af0b39ea45d4bf04959bf0ea42ed23b24aeadb`.
This slice changes only parse_proc_io_field and adds one selftest invocation
in that script, the new stopwatch_io_counter_selftest.sh, and this note.
All other pending work and the existing staged diff were preserved.

Measured on Linux x86_64, AMD EPYC 7402P, Bash 5.2.21 and GNU awk 5.2.1.
The fixture uses an in-memory seven-line kernel-format record with warm tool
caches and uncontrolled host load. It retains the caller's command
substitutions. No node, datadir, RPC, network or sleep participates.

| Measurement, 500 read/write pairs | Before | After |
|---|---:|---:|
| External parser invocations per pair | 2 | 0 |
| Wall time | 4.894 s | 1.241 s |
| User + system CPU | 5.834 s | 1.342 s |

Wall time is one before/after observation, not a timing threshold. The
deterministic gate is zero external parser calls. This establishes reduced
observer overhead, not an end-to-end IBD or time-to-tip improvement.

Reproduce with:

```bash
bash tools/scripts/stopwatch_io_counter_selftest.sh --bench
```

An optional final argument selects a saved baseline stopwatch. The baseline
passes the value fixtures and fails the process budget. Coverage includes
zero, absent and malformed counters, similarly named fields, duplicate rows,
whitespace, unterminated final lines, leading zeros and unsigned 64-bit text.
A mutation removing the numeric check fails the regression.

The complete cold-start stopwatch selftest, artifact-symmetry selftest and
evidence-judge selftest pass. Shell syntax and git diff --check pass. Existing
shell-host-assumption, discarded-status, pipefail-status, no-API-keys,
no-Python and architecture checks pass. The core seal verifies all 554 files
and 80 sections; the exported root mirror matches. This shell-only slice
needs no compiler change. No consensus, validation, acceleration policy,
Hetzner-owned scheduling, database or node runtime behavior changes.

Aggregate validation is incomplete: make lint-fast exceeded its 50-second
bound during setup without reporting gate results. The public node binary
is absent. These focused fixtures do not replace publication acceptance.

Publication is blocked. Git add failed because .git/index.lock cannot be
created on the read-only filesystem. Fetch also failed on read-only
.git/FETCH_HEAD; the origin branch query failed on GitHub DNS. No commit,
push or remote-SHA equality is claimed. The branch remains unchanged. No
secrets, logs, binaries, generated artifacts or temporary benchmark output
are included in this slice.
