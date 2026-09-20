<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream import-copy height observer cost

The recovery/startup proof in `tools/scripts/import-copy-prove.sh` starts
`sed` and `head` for each `getblockcount` observation. Letting sed quit after
its first successful substitution removes one process per poll. The exact
substitution, RPC count, polling interval, deadlines, climb threshold,
continuity check and hash-parity check remain unchanged.

Baseline: `agent/worldstream-ibd-20260918` at
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Baseline harness SHA-256:
`cad45bd71d9cefca3f2386b8a1d53b1b8226e5d6d1a661457ed85f5b7f6f7dc4`.
Both edited existing scripts were clean before this slice. Other staged and
unstaged Worldstream work is excluded.

Measured on Linux x86_64, AMD EPYC 7402P, GNU sed 4.9, warm caches and
uncontrolled host load. The isolated fixture extracts the real observer,
stubs RPC and neither starts a node nor accesses a datadir or network.
Each timed invocation includes 20 correctness cases, 300 repeated reads
and three process-count probes. Three alternating baseline/updated trials:

| Measurement | Baseline | Updated |
|---|---|---|
| External parser processes per observation | 2 | 1 |
| Wall seconds | 0.97, 0.98, 0.99 | 0.97, 0.97, 0.96 |
| User + system CPU seconds | 1.60, 1.64, 1.65 | 1.14, 1.13, 1.13 |

Median CPU cost fell approximately 31%; elapsed time changed little. This is
observer overhead evidence, not an end-to-end IBD or time-to-tip result.

Reproduce without build prerequisites:

```sh
sh tools/scripts/import_copy_tip_selftest.sh
time sh tools/scripts/import_copy_tip_selftest.sh --bench
time sh tools/scripts/import_copy_tip_selftest.sh --bench /path/to/baseline.sh
bash tools/scripts/import-copy-prove-selftest.sh
```

The baseline passes all output checks but fails the one-parser-per-read
bound (six launches for three observations). The updated reader passes
under both sh and Bash. Cases pin negative, zero, wide and leading-zero
values, missing/null/quoted responses, whitespace, exact key names,
same-line and multiline duplicates, later matching lines and the existing
integer-prefix behavior. An unconditional-quit mutation fails the later-line
case. The new regression runs from the existing import/bundle selftest;
all 24 existing driver scenarios also pass in the original and isolated
checkouts, including refusal, persistent-gap and hash-mismatch cases.

Shell syntax, architecture, shell-host assumptions, discarded-status,
pipefail-status-pipe, no-API-keys, no-Python, warning-suppression and
consensus-parity checks pass. The core seal verifies 554 files and 80
sections. No node/runtime/consensus, peer scheduling, database, cryptographic
or optional-acceleration behavior changes. Only source, tests and this
measurement note belong to the slice; generated files and raw results do not.

The original checkout's Git metadata is read-only. A separate writable
checkout at `/tmp/worldstream-ibd-slice` contains only this slice on the same
development branch. Full `make lint` was attempted there; vendor zlib
downloads failed because GitHub DNS was unavailable, and the incomplete run
was stopped. Its lint runtime did build with strict C23 warnings. Full lint
and real-node sync acceptance remain unverified. Origin fetch also fails
DNS; no remote-SHA equality or successful publication is claimed.
