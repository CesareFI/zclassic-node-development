<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream startup observer: remove redundant parser processes

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`.

The read-only startup observer in `tools/scripts/ship_progress_lib.sh`
starts a separate sed before each awk reader of CPU, process-start and
blocked-I/O counters. A sample therefore starts six external parsers.
Move the identical greedy process-name stripping into each existing awk.
This removes three external processes per sample while retaining field
numbering, first-usable-line selection, numeric formatting and zero defaults.
There is no change to polling cadence, classification or rollback authority.

The new hermetic regression compares all three readers with their original
pipeline on 39 inputs: empty/malformed text, nested parentheses in names,
multiple lines and every field-count boundary from 12 through 40. It also
counts sed invocations. The original implementation produces 117 and fails
the zero-sed budget; the revised implementation produces zero with identical
outputs. The existing ship selftest invokes this regression.

## Measurement

Linux x86_64, 48 reported logical CPUs, GNU Awk 5.2.1. Each warm, in-memory
run parses 300 samples (900 reader calls), with no node, datadir or network.
These are sequential paired microbenchmarks, not time-to-tip observations.
The initial baseline was 4.366 seconds. Repeated wall times:

| Pair | Original seconds | Revised seconds |
| --- | ---: | ---: |
| 1 | 4.265 | 3.938 |
| 2 | 4.352 | 3.976 |
| 3 | 4.300 | 3.768 |

Median wall time declines from 4.300 to 3.938 seconds (8.4%). The deterministic
result is 900 fewer external processes per 300 samples. Timing depends on
host load; no timing threshold is imposed and no end-to-end IBD speedup is
claimed. Binary hashing and RPC observation costs remain outside this test.

## Reproduction

```bash
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/ship_progress_lib.sh > /tmp/ship-progress-before.sh
bash tools/scripts/ship_proc_parser_selftest.sh --baseline /tmp/ship-progress-before.sh --bench
bash tools/scripts/ship_proc_parser_selftest.sh --bench
bash tools/ship_selftest.sh
bash tools/lint/check_ship_remote_transaction.sh
```

Focused fixtures, the full hermetic startup observer test and the isolated
remote transaction test pass. POSIX syntax of the production library and
Bash syntax of the tests pass. Architecture, shell-host-assumption,
discarded-status and pipefail-status-pipe checks pass when run directly.
`git diff --check` passes. No compiled implementation changes in this slice.

Full `make lint` is not a passing result: the clean-clone attempt encountered
failed GitHub DNS while fetching zlib and reached its 60-second bound during
prerequisite compilation. The separate `tools/ship.sh --selftest` front-door
check could not complete because `check_no_hardlink_seeding` was unavailable.
These limits do not replace either gate with the narrower passing tests.
Remote fetch also fails DNS; upstream integration and publication cannot be
claimed. The workspace Git metadata is read-only, so the isolated commit is
prepared in `/tmp/worldstream-startup-parser-slice` on the same development
branch, preserving all pre-existing staged and unstaged work.

Consensus, cryptography, node runtime, scheduling, storage tuning and all
validation remain unchanged. Z23 acceleration remains optional. The only
production edit is to shell parsing of already-captured process statistics.
No production service or datadir was touched; logs and benchmark output are
excluded from the commit.
