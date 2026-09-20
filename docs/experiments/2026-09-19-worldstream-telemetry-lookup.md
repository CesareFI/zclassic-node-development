<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reduce sync telemetry lookup cost

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The sync summary renderer repeatedly resolves fields through the ontology's
linear lookup. Adjacent rows commonly share one subsystem string, but every
row compared that string again. Retain the previous pointer and its comparison
result within each lookup. A different pointer always triggers a new comparison,
including equal strings in separate storage and interleaved subsystem groups.
First-match behavior is unchanged. There is no persistent cache, allocation,
lock, generated index or new authority.

The ontology source was clean at entry; its baseline SHA-256 is
`2fcb7a311b2ddc27e054e18bd64a91aa42b493b2087f27312d7011dfe4a16342`.
This slice owns that function, a standalone regression/benchmark, its Makefile
target and this report. Extensive unrelated staged and unstaged work remains
outside the slice.

## Measurement

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, C23 at `-O2`. Synthetic in-process
snapshots and warm immutable tables; baseline and candidate alternate on the
same host under ambient load. No node, network, chain fixture or production
datadir participates. These measurements describe observer overhead, not an
end-to-end IBD or time-to-tip improvement.

| Workload | Baseline | Candidate |
|---|---:|---:|
| String comparisons to look up all 44 sync fields | 11,792 | 1,342 |
| 440,000 lookups, milliseconds, three runs | 436.130 / 442.147 / 435.022 | 164.210 / 163.997 / 163.654 |
| 10,000 complete sync summaries, milliseconds, three runs | 739.646 / 718.089 / 715.360 | 461.905 / 469.897 / 465.160 |

Median lookup time fell 62%; median complete summary time fell 35%. Actual
savings depend on compiler string pooling and the table layout. Correctness
does not: the regression explicitly uses equal names with distinct storage,
interleaved groups, duplicate keys and caller-owned strings.

Reproduce the standalone measurement with:

```sh
bash tools/scripts/telemetry_lookup_selftest.sh
bash tools/scripts/telemetry_lookup_selftest.sh --baseline /path/to/baseline.c
ANALYZE=1 bash tools/scripts/telemetry_lookup_selftest.sh
```

The fixed fixture deterministically requires 10 string comparisons; the entry
baseline uses 11 and fails that assertion. Every real ontology field, missing
key and NULL input is also checked against an independent linear oracle.
Timing values are reported, never used as pass/fail thresholds.

The broader summary measurement reuses the pre-existing working-tree
`telemetry_sync_summary_selftest.sh` harness (SHA-256
`54e13f76bb0f95bfabf41f8009028de6d271121d06761ff45e36a1d867963017`)
and native command source (SHA-256
`253ffa2a81015b57662eb171814772dbe0a9b724fa7bf1afbc69c0a9d09c98d6`).
Only the ontology source varies. Twelve encoded replies and their next actions
are byte-identical between baseline and candidate. This harness and command
contain earlier work and are not included in this slice.

## Validation and limits

The standalone regression compiles with `-Wall -Wextra -Werror`; GCC
`-fanalyzer` passes. AddressSanitizer and UndefinedBehaviorSanitizer pass both
the lookup and existing summary harness, including allocation failure,
unavailable snapshots, oversized replies, health states and stage projections.
LeakSanitizer is unavailable under the sandbox's tracing; those runs explicitly
disable leak detection and claim no leak-check result.

Ontology coverage, architecture tree, shell syntax, shell host assumptions,
pipefail status, discarded status, JSON initialization and the wall-clock
assertion gate pass. The exact slice diff and `git diff --check` pass.

The canonical `t-fast ONLY=telemetry` selects 13 groups but cannot initialize
the missing Tor submodule because `.git/config` is read-only; it was bounded
at 50 seconds. The documented offline-stub build selected the same groups but
exceeded a 180-second bound during initialization without executing them.
`make check-telemetry-ontology` and `make lint-fast` each exceeded a 50-second
initialization bound; their relevant standalone checks above were run directly.
No aggregate lint, canonical registered-group, public-node or live-chain
acceptance pass is claimed.

Consensus, cryptography, wallet custody, optional acceleration policy and
Hetzner-owned scheduling, database and runtime behavior are unchanged. Only
read-only telemetry name lookup changes. No secrets, generated artifacts,
logs, caches, binaries or benchmark output belong to this slice. Scratch
sources, measurements and the isolated patch are under
`/tmp/worldstream-ontology-lookup/`.

Publication remains incomplete. Git accepted staging of the source and test,
but subsequent staging and an isolated-index application failed because Git
object/index storage is read-only. Fetch cannot write `FETCH_HEAD`; remote
branch lookup cannot resolve GitHub. No commit, push or exact remote-SHA
verification is claimed. The isolated patch includes only this slice's
Makefile hunk; staging the entire dirty Makefile would include unrelated work.
