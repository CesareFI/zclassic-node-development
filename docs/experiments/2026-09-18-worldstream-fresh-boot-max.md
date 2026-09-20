<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fresh-boot log maximum

The fresh-boot proof sorted all matching log heights twice per sample to
find the header and chain maxima. Replace each four-process pipeline with
grep plus an awk maximum reduction. This removes sorting and storage of the
entire matching-height set; log scanning remains linear in the full log size.
The next potential cost is repeated full-log scanning, which this slice does
not eliminate.

Owned files: `tools/scripts/fresh-boot-proof.sh`, its new
`tools/scripts/fresh_boot_log_max_selftest.sh`, and this note. The reader was
clean at HEAD `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`; unrelated staged and unstaged Worldstream
work was preserved. Baseline reader SHA-256:
`53a5cae543e5cc794121f4714cb1b252958b21741d3712867d22e864988630e2`.
Updated reader SHA-256:
`235838c567685201d3e9f6183f28b5effeec8cc8f01c3bf86886dfb0af80c592`.

On Linux x86_64, AMD EPYC 7402P, GNU awk 5.2.1, the generated fixture has
200,000 lines / 9,466,680 bytes. Ten samples each read both maxima, using
warm filesystem caches and uncontrolled host load. No node, datadir, peer,
network, or sleep is involved.

| Measurement | Before | After |
| --- | ---: | ---: |
| Parser processes per sample | 8 | 4 |
| Wall time, ten samples | 3.828 s | 2.092 s |
| User + system CPU, ten samples | 6.277 s | 4.093 s |

These are instrumentation costs, not IBD or time-to-tip results. Reproduce:

```bash
bash tools/scripts/fresh_boot_log_max_selftest.sh --bench
```

An optional final script path measures a saved baseline. The original reader
passes all 18 behavior checks and fails the four-process regression gate.
The updated reader passes with GNU awk and mawk. Cases cover missing/empty
logs, absent values, zero, numeric ordering, multiple matches on one line,
duplicates, lower later heights, leading zeros, exact wide integers and
numeric ties, integer prefixes, incomplete final lines, truncation, and
replacement. A minimum-instead-of-maximum mutation fails numeric ordering.
The process count is the deterministic gate; timing is informational.

The stopwatch artifact-symmetry and evidence-judge selftests pass, as do Bash
syntax, whitespace, architecture, shell-host assumptions, pipefail-status-pipe,
discarded-status, no-API-keys, no-Python, and no-warning-suppression checks.
The core seal verifies all 554 files and 80 sections unchanged. This slice
changes no runtime, scheduling, storage, consensus, validation, acceleration
policy, verdict, or acceptance threshold. It includes no secrets, generated
files, logs, binaries, caches, or benchmark output.

Publication remains blocked: `.git` is read-only, so fetch cannot write
`FETCH_HEAD`; `origin/main` is absent locally. Querying the exact development
branch on origin fails because GitHub DNS is unavailable. Full `make lint`
reached a 45-second bound during prerequisite compilation after a dependency
download failed on DNS. Commit, push, full integration acceptance, and remote
SHA verification are not claimed. The session leaves only this three-file
slice in addition to the pre-existing work.
