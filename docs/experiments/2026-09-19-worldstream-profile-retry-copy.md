<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound profile counter retry copying

Branch: `agent/worldstream-ibd-20260918`; HEAD at entry:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The `jnums1` fold-profile observer copied the entire remaining response each
time it retried an unavailable or ineligible occurrence of a requested counter.
Dense repetitions made this copying quadratic. The reader now uses the same
nearby-key search already present in `jnums`: search 256 bytes plus key-length
overlap, then search the remaining suffix only after a miss. First usable
integer selection, comma/quote boundaries, exact integer text, missing-value
zeros and input draining are unchanged.

This slice changes only that retry search, adds a standalone regression and
this record. The checkout already contained extensive staged, unstaged and
untracked work. Its existing reader implementations are prerequisites, not
changes authored here. Baseline working-script SHA-256:
`63df68da10c517a6639dcb8392256ffa65e3760cb6fb2c3b7944c232b3866200`.
The baseline, timing output and source-only slice patch are temporary evidence
under `/tmp/worldstream-profile-retry/`. Do not stage the whole dirty sampler
as this slice.

## Measurement

Linux x86_64, GNU awk 5.2.1, POSIX shell, warm tools and ordinary filesystem
caches. Three sequential baseline/candidate repetitions; ambient load was
uncontrolled and lint initialization overlapped part of the measurement.
Fixtures contain repeated `blocks:null` entries followed by a usable wide
integer and a later duplicate. This is synthetic observer stress, not evidence
that real node responses contain this many duplicate fields, nor a measured
end-to-end IBD bottleneck or time-to-tip improvement.

| Measurement | Baseline | Candidate |
|---|---:|---:|
| Retry-search substring bytes, 1,000 unavailable entries | 7,035,000 | 263,112 |
| Retry-search substring bytes, 10,000 unavailable entries | 700,350,000 | 2,648,112 |
| 20 reads, 1,000 entries, wall seconds | 0.13 / 0.12 / 0.13 | 0.13 / 0.13 / 0.13 |
| 20 reads, 10,000 entries, wall seconds | 0.79 / 0.77 / 0.78 | 0.47 / 0.47 / 0.47 |
| 500 ordinary complete-profile reads, wall seconds | 2.17 / 2.18 / 2.16 | 2.17 / 2.19 / 2.22 |

The large retry fixture's median wall cost falls about 40%. Ordinary complete
responses show no improvement and vary within approximately 3%. The byte
counter observes only retry-search substrings, not total allocations or RSS.
Sparse retry gaps still use the full-suffix fallback; this is not a general
linear-complexity guarantee for arbitrary input.

## Validation

```sh
sh tools/scripts/fold_profile_retry_cost_selftest.sh --bench
sh tools/scripts/fold_profile_scan_selftest.sh
sh tools/scripts/fold_profile_selftest.sh
sh tools/scripts/fold_profile_rpc_selftest.sh
sh tools/scripts/fold_profile_drive_selftest.sh
sh tools/scripts/fold_profile_summary_selftest.sh
sh tools/scripts/fold_profile_missing_keys_selftest.sh
sh tools/scripts/fold_profile_boundary_selftest.sh
sh tools/scripts/fold_profile_prefix_selftest.sh
```

All pass. The new regression also passes under mawk and BusyBox awk. It fails
on the baseline's copying budget, and a mutation that removes key overlap
fails the split-key fixture. Coverage includes distant keys, keys longer than
the search window, unavailable-only input, repeated requested keys, wide
integers and ineligible nested occurrences. Broader tests preserve the exact
50-column CSV, five-parser budget and 35 RPC refusal/recovery cases.

POSIX/Bash syntax checks, native architecture and shell-host-assumption gates,
shell pipefail/discarded-status gates and `git diff --check` pass. Full
`make lint-fast` timed out after 60 seconds during initialization; no aggregate
lint pass is claimed. ShellCheck and the public node binary are unavailable.
No C source changed, so compiler and live-chain acceptance were not run.

Consensus, cryptographic validation, optional acceleration policy and
Hetzner-owned scheduling/database/runtime behavior are untouched. The slice
contains source, a fixture test and documentation only, with no secrets,
production state, logs, binaries or generated artifacts.

Publication remains incomplete. `origin` has no `main` ref. Initial development
branch fetches failed on read-only `.git/FETCH_HEAD`; a later retry succeeded
and recorded the unchanged entry SHA. The separate remote lookup still failed
to resolve GitHub. In addition, `jnums1` itself belongs to earlier uncommitted
work, so committing the full sampler would absorb changes outside this slice.
No commit, push or independent remote-SHA verification is claimed. The
aggregate lint gap and uncommitted prerequisites remain publication gates.
