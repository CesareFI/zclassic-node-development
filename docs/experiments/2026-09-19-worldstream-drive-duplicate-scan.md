<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: skip absent duplicate scans in the fold observer

Branch: `agent/worldstream-ibd-20260918`; HEAD at entry:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold-profile drive reader searched the remaining response with a regex
after every successful scalar or stage match, even when no further occurrence
of that literal key existed. Diagnostic tails therefore added an unnecessary
regex search per observed column. The loop now checks literal presence first.
Last valid occurrence on the first matching line, malformed-field handling,
missing-value zeros, exact integer text and CSV order remain unchanged.

This slice changes only that loop, strengthens the existing sparse-drive
selftest with a diagnostic suffix and a two-scan budget, and adds this note.
The extensive earlier changes in this checkout are prerequisites, not part of
this slice. Working-source baseline SHA-256:
`ebe46caa0e251496581c5ec9d4e8689fe5a37193d31e57a380bdbbcd9313cc2d`.
The preexisting selftest baseline SHA-256:
`7bb84e87e67cbb668db277b93a67af99a9ca90b726c78311e18fdaf9d796f7f9`.
Entry snapshots and the isolated incremental patch are under
`/tmp/worldstream-drive-suffix/`. Do not stage either whole modified script
as an isolated change: both already contained unrelated work.

## Measurement

Linux x86_64, GNU awk 5.2.1, POSIX shell, warm tools and filesystem caches.
The synthetic 2,155,651-byte response has diagnostic prefixes and suffixes,
one scalar and one stage object. Each read requests eight scalars and eight
stages. No node, network, production datadir or chain input participates.

| Measure | Baseline | Candidate |
|---|---:|---:|
| Regex calls per read | 4 | 2 |
| Bytes presented to regex per read | 3,711,335 | 1,855,699 |
| Wall seconds for 30 reads, three runs | 2.59 / 2.59 / 2.60 | 2.53 / 2.56 / 2.56 |

The deterministic improvement is half as many regex calls. Literal searching,
string copying and process costs remain. The roughly 1% median wall reduction
is small; host load was uncontrolled and a bounded lint attempt overlapped
the measurements. These numbers establish no end-to-end IBD improvement.

Reproduce the candidate with:

```sh
sh tools/scripts/fold_profile_drive_sparse_selftest.sh --bench
```

Pass `--baseline --bench /path/to/baseline.sh` to report the earlier reader.
Without `--baseline`, the earlier reader fails the tightened two-scan budget
while returning the same CSV. This negative control was exercised.

## Validation and limits

All 11 `fold_profile*_selftest.sh` scripts pass, including exact 50-column
sampling, 35 RPC refusal/recovery cases, history summaries, and parser work
budgets. Sparse-drive and full CSV selftests also pass under mawk and BusyBox
awk. POSIX shell and Bash syntax checks pass. Shell-host-assumption,
discarded-status, pipefail-status and architecture-tree gates pass using their
existing direct entrypoints. `git diff --check` passes. ShellCheck is absent;
no C changed, so no compiler test is applicable to this slice.

`make lint-fast` timed out after 50 seconds during initialization, before
aggregate gate results. Aggregate lint is not claimed green. The public node
binary is absent, so built-in navigation and live IBD measurement were not
available. The core seal verifies all 554 sealed files and 80 sections.
Consensus, validation, optional acceleration policy, Hetzner-owned scheduling,
database tuning and node runtime code are unchanged. The incremental diff
contains no secrets, logs, caches, binaries or generated artifacts.

Publication remains incomplete: fetching cannot write `.git/FETCH_HEAD`
because `.git` is read-only, and remote lookup cannot resolve GitHub. No
commit, push or local/remote SHA equality is claimed. The branch was retained.
