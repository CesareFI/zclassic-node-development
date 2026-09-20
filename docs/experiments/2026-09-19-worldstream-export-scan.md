<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: remove a diagnostic scan before snapshot export

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5`, development branch
`agent/worldstream-ibd-20260918`. Owned surface: the standalone optional
`snapshot_from_coinskv` tool. No node, consensus, scheduler, database tuning,
snapshot writer, loader or cryptographic code changes.

The tool called `coins_kv_setinfo` solely to print count and supply before
export. Its SQLite path computes `COUNT(DISTINCT txid)`, `COUNT(*)` and
`SUM(value)` across the coins set. The transaction count was unused, and the
query's failure did not prevent export. This was diagnostic work, not a
validation check. The existing canonical writer already returns count,
supply and body digest after successfully writing the artifact.

Remove that preliminary call and its progress message. Keep the final
`WROTE` report, writer arguments, shielded collection/release and all error
returns. Optional acceleration stays optional; normal independent Zclassic
validation retains its authority.

## Measured evidence

Linux x86_64, kernel 6.8.0-139-generic, GCC 14.2.0, `-std=c23 -O2`.
The isolated fixture contains 100,000 deterministic coins rows in an
in-memory SQLite `WITHOUT ROWID` table, with duplicate transaction IDs and
two outputs per transaction except the endpoints. This is warm memory,
without peers, production state or network load. Timings isolate the
diagnostic aggregation, excluding fixture construction and export work.

| Mode | Before scan steps | After scan steps | Before query time | After query time |
|---|---:|---:|---:|---:|
| Coins only | 99,999 | 0 | 26.440 ms | 0 ms (query absent) |
| Shielded | 99,999 | 0 | 25.838 ms | 0 ms (query absent) |

These are single-run observations, not latency percentiles or an end-to-end
IBD improvement. The deterministic regression is the query/scan count,
not a machine-dependent timing threshold.

## Reproduction and boundaries

```bash
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/snapshot_from_coinskv.c > /tmp/export-before.c
bash tools/scripts/snapshot_export_scan_selftest.sh --baseline /tmp/export-before.c
ANALYZE=1 bash tools/scripts/snapshot_export_scan_selftest.sh
SANITIZE=1 bash tools/scripts/snapshot_export_scan_selftest.sh
```

The fixture compiles the actual CLI against repository headers, extracts
the actual SQLite aggregation implementation, and uses a recording writer.
It checks coins-only/shielded dispatch, height and hash byte order, final
reported outputs, cleanup on writer failure, store failures, unavailable
shielded state, and invalid CLI arguments. The revised scan budget fails
on the original source. It does not execute the real snapshot writer or
claim artifact-byte or chain-sync acceptance.

On this host only the system SQLite runtime library is installed; use
`SQLITE_LIBS=-l:libsqlite3.so.0`. AddressSanitizer and UndefinedBehaviorSanitizer
pass with `ASAN_OPTIONS=detect_leaks=0`; LeakSanitizer cannot run under the
host's ptrace environment. GCC `-fanalyzer`, strict warning compilation of
both the fixture and the production translation unit, and bash syntax pass.
The seven directly run lint gates pass: architecture tree, malloc, raw SQLite,
discarded shell status, pipefail status pipes, warning suppression, and stray
untracked source. The lint runtime was compiled locally from its tracked C23
sources because the umbrella build could not acquire its vendor dependencies.

The registered `snapshot_shielded` group and full `make lint` were attempted
but blocked before completion by unavailable vendor dependencies and failed
DNS for their downloads. They are not reported as passing. No production
datadir was opened. Benchmark output and compiled files remain outside Git.

The remaining export cost is in the unchanged canonical writer and its
serialization/digest work; measuring that on an isolated representative
dataset is a separate slice. No bottleneck ranking against live IBD is claimed.
