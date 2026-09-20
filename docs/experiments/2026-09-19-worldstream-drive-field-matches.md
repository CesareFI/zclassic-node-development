<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: extract drive fields without copying diagnostic prefixes

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold-profile observer used a greedy leading `.*` for each drive counter
or stage. Extracting a field near the end of a compact response copied its
entire prefix, then scanned that prefix again to remove it. `jnums` now
matches only the field and walks subsequent occurrences, retaining the last
valid match on the first matching line. Missing values, duplicate requested
keys, exact wide integer text, stage triples and input draining are preserved.

The owned implementation delta is confined to `jnums` in
`tools/scripts/fold_profile.sh`. The existing
`tools/scripts/fold_profile_scan_selftest.sh` gains a diagnostic-prefix
fixture, a matched-byte budget, duplicate-value coverage and optional timing.
Both files already contained earlier work at entry; do not stage their whole
diffs as this slice. Entry snapshots and the isolated implementation/test patch
are under `/tmp/worldstream-drive-matches/`, outside tracked source.

The baseline is the working script at entry, SHA-256
`06f036e9d721821069d9cee89127010bdbc6f18f1f5b8d26de411e0d23e6e813`,
not pristine HEAD. The resulting script is
`1f45e676320b81d8140fd49657f1d69aa96bbc655ad614145d2680bcb1c8e34d`.

## Measurement

Linux x86_64, GNU awk 5.2.1 and POSIX shell, warm tools/filesystem caches,
uncontrolled ambient load. Three sequential baseline/candidate pairs each
read a synthetic 227,871-byte response 100 times: 10,000 diagnostic fields
precede two requested scalars and one stage triple. Some timing overlapped
local validation. No node, peer, network, RPC or datadir participates.

| Measurement | Baseline | Candidate |
|---|---:|---:|
| Extracted match bytes per read | 683,495 | 78 |
| Wall seconds, three runs | 1.34 / 1.35 / 1.34 | 0.93 / 0.94 / 0.92 |
| User CPU seconds | 0.94 / 0.93 / 0.92 | 0.55 / 0.52 / 0.53 |
| Maximum RSS, KiB | 4,608 | 4,608 |

Median stress-fixture wall cost fell about 31%. A separate 200-complete-sample
fixture measured 5.39 seconds before and 5.17 after, one run each; that is
insufficient to establish a stable whole-sampler improvement. Five parser
processes remain per sample. Missing fields still scan the response, and
duplicate fields still require finding the last valid occurrence. These
measurements establish neither real IBD throughput nor time-to-tip improvement.

## Validation and limits

```sh
sh tools/scripts/fold_profile_scan_selftest.sh --bench
sh tools/scripts/fold_profile_selftest.sh
sh tools/scripts/fold_profile_rpc_selftest.sh
sh tools/scripts/fold_profile_drive_selftest.sh
sh tools/scripts/fold_profile_summary_selftest.sh
sh tools/scripts/fold_profile_history_selftest.sh
```

All pass. The scan regression also passes with mawk and BusyBox awk. The
baseline passes value checks and fails the new matched-byte ceiling. A
mutation selecting the first duplicate instead of the last fails value checks.
Related checks cover exact CSV columns, fifteen RPC refusals and recovery,
wide durations, missing observations and long-history summaries.

POSIX/Bash syntax, architecture-tree, shell-host-assumption, pipefail-status,
discarded-status and `git diff --check` pass. `make lint-fast` timed out after
60 seconds during initialization; no aggregate lint pass is claimed. The
public binary is absent. `make -j2 z23` encountered read-only Git metadata
while initializing Tor and was interrupted; no node build or live-chain test
is claimed. ShellCheck is unavailable. No compiled source changed.

The exact slice diff was reviewed: consensus, cryptographic validation,
optional acceleration policy and Hetzner-owned code are unchanged. Earlier
dirty work is preserved. No secrets, wallets, production state, logs, caches,
binaries or generated build output belong to this slice.

Publication remains incomplete: fetch cannot write `.git/FETCH_HEAD`, and
the origin branch lookup cannot resolve GitHub. No commit, push or verified
remote SHA is claimed. Aggregate lint and publication remain outstanding.
