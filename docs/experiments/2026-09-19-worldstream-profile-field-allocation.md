<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: avoid splitting unused profile fields

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The existing fold-profile reader stopped visiting fields once every requested
counter was found, but still split the entire first response line into an awk
array. A large diagnostic tail therefore allocated thousands of unused fields
on every sample. `jnums1` now searches each requested column directly, using
the same first-quote, comma and line boundaries. It preserves first integer
matches, cumulative-before-last-batch selection, exact integer text, duplicate
requested keys and missing-value zeros. Input still drains to EOF.

Only the `jnums1` implementation and its existing scan regression changed in
this slice. Earlier staged, unstaged and untracked work remains intact. In
particular, batching and other reader changes already present in this checkout
are prerequisites, not changes authored here. The baseline is the working
script at entry, SHA-256
`18dea445276fa4a0be6a2ee56673e57457aff6adf0f356503802cee3b95cf051`,
not pristine HEAD. Baseline snapshots and the isolated slice patch are in
`/tmp/worldstream-profile-fields/`; they are temporary development evidence.

## Measurement

Linux x86_64, GNU awk 5.2.1, POSIX shell, warm tools and ordinary filesystem
caches. Three repetitions run baseline then candidate sequentially, with
uncontrolled ambient host load. The first two repetitions overlapped a bounded
lint initialization attempt. Responses are synthetic: two cumulative counters
followed by unused diagnostic fields. No node, RPC, peer, chain data or
production datadir participates. These are observer-cost measurements, not
end-to-end IBD or time-to-tip results.

| Measurement | Baseline | Candidate |
|---|---:|---:|
| 500 reads, 10,402-byte response, wall seconds | 2.28 / 2.28 / 2.28 | 2.15 / 2.14 / 2.17 |
| 100 reads, 1,227,829-byte response, wall seconds | 3.58 / 3.58 / 3.59 | 1.83 / 1.83 / 1.85 |
| Large-response maximum RSS, reported by `time`, KiB | 14,208 | 6,144 |
| Column probes across two response lines | 6 | 2 |

Median wall cost fell about 6% for the small fixture and 49% for the stress
fixture. Missing columns still require searching the full input; process
startup and response transport remain. No new throughput claim is made for
real IBD.

## Validation

```sh
sh tools/scripts/fold_profile_scan_selftest.sh --bench
sh tools/scripts/fold_profile_selftest.sh
sh tools/scripts/fold_profile_rpc_selftest.sh
sh tools/scripts/fold_profile_drive_selftest.sh
sh tools/scripts/fold_profile_summary_selftest.sh
```

The scan regression passes under GNU awk, mawk and BusyBox awk. It covers
eleven value fixtures, the column-probe budget and large multiline input under
pipefail. The baseline passes the value fixtures and fails the new work budget
with six probes. A greedy-match mutation fails cumulative-counter selection.
Broader sampler tests pass for exact CSV values, five-parser accounting,
fifteen RPC refusal cases and recovery, and wide-duration summaries.

Bash and POSIX shell syntax, architecture-tree, shell-host-assumption,
pipefail-status and discarded-status gates pass. Both staged and unstaged
`git diff --check` pass. A fresh `make lint-fast` attempt on 2026-09-20 was
still silent after template generation for more than four minutes and was
interrupted; a separately requested bundle of the four focused make gates was
likewise still in shared initialization after two minutes. No new full lint
pass is claimed. ShellCheck and the public node binary are unavailable. No C
source changed, so compiler and live-chain tests were not run for this slice.

Consensus, cryptographic validation, optional acceleration policy, and
Hetzner-owned scheduling, database and runtime code are unchanged. The reviewed
slice contains no secrets, logs, binaries, caches or generated build output.

Publication is incomplete: branch fetch cannot write `.git/FETCH_HEAD` on the
read-only filesystem, and the remote branch lookup cannot resolve GitHub.
No commit, push or exact remote-SHA verification is claimed. Do not stage the
whole dirty sampler or regression as this slice: each contains earlier work.
The aggregate lint gap also prevents declaring the slice ready for publication.
