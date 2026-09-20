<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound stage-counter regex scans

Branch: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold profiler passed the entire remaining diagnostic response to each
stage-counter regex. It now stops that regex input at the first closing brace,
which a valid stage triple cannot cross. Malformed objects still permit later
valid occurrences; first matching line, last valid duplicate, wide integer text,
missing-value zeros and comma-terminated triples retain their existing behavior.
Duplicate-key searches and initial suffix copies still inspect the full line.
This does not establish bounded total parser cost for arbitrary malformed input.

This slice changes only `jnums` in `tools/scripts/fold_profile.sh`, adds
`tools/scripts/fold_profile_stage_object_selftest.sh`, and registers that test
under `make fold-profile-selftest`. Both existing files had unrelated changes
at entry. The baseline is the entry working script, SHA-256
`fda21900aba1399bcc05c2285959b0d808b2e84360ef1b6653dc6d29ba1d16c0`,
not pristine HEAD. Entry snapshots, temporary measurements and the isolated
slice patch are under `/tmp/worldstream-stage-object/`. Do not stage either
whole existing file as this slice. The original index remains unchanged.

## Measurement

Linux x86_64, GNU awk 5.2.1, POSIX shell, warm tools/filesystem caches,
uncontrolled ambient load. Three sequential baseline/candidate pairs each run
100 reads of four synthetic stage objects followed by diagnostic fields. A
bounded aggregate lint initialization overlapped part of the measurement.
No node, network, chain, production datadir or real time-to-tip measurement
participates; these figures measure observer overhead only.

| Diagnostic fields | Baseline wall seconds | Candidate wall seconds |
|---|---|---|
| 0 | 0.49 / 0.50 / 0.50 | 0.49 / 0.50 / 0.50 |
| 500 | 0.51 / 0.52 / 0.52 | 0.52 / 0.52 / 0.51 |
| 50,000 | 3.25 / 3.30 / 3.26 | 2.95 / 2.93 / 2.95 |

The large fixture's median fell about 9.5%. Reported maximum RSS fell from
10,444 KiB to 7,924–7,952 KiB. Its four regex calls consume 163 bytes instead
of 4,911,602 bytes. The regression measures actual regex input lengths rather
than asserting elapsed time under variable host load.

## Validation

```sh
sh tools/scripts/fold_profile_stage_object_selftest.sh --bench
make fold-profile-selftest
sh tools/scripts/fold_profile_summary_selftest.sh
sh tools/scripts/fold_profile_counts_selftest.sh
sh tools/scripts/fold_profile_history_selftest.sh
```

These pass. The new regression passes with GNU awk, mawk and BusyBox awk,
including malformed/duplicate/nested stages, extra fields, incomplete objects,
wide integers and multiline responses. The entry baseline fails its regex-work
budget. A mutation that stops after a malformed object fails the value checks.
Existing exact 50-column CSV, scalar windows, sparse telemetry, RPC refusals,
RPC deadlines, recovery and summary tests pass. POSIX/Bash syntax, architecture,
shell-host assumptions, pipefail-status and discarded-status checks pass.
`git diff --check` passes. No C source changed; no compiler or live-chain result
is claimed.

`make lint-fast` exceeded 50-second and 180-second bounds during initialization;
no aggregate lint pass is claimed. `make check-architecture-tree` likewise
exceeded its 30-second bound during initialization, while invoking its checker
directly passed. Generated templates reported unchanged. These outstanding
aggregate checks prevent declaring the slice ready for publication.

Consensus, cryptographic validation, optional acceleration policy and all
Hetzner-owned scheduling/database/runtime code remain unchanged. The slice
contains source, regression and documentation only, with no credentials,
production data, logs, caches, binaries or generated output.

Publication is incomplete: fetching cannot write `.git/FETCH_HEAD` on the
read-only filesystem, and `git ls-remote origin` cannot resolve GitHub.
No commit, push or exact remote-SHA verification is claimed.
