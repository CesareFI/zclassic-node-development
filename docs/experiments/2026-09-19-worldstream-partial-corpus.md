<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: refuse partial deserialization benchmark workloads

The standalone `serial_bench` tool silently skipped malformed hex records.
Consequently a damaged corpus could report verified throughput for a different,
smaller workload. This prevents trustworthy comparison of the deserialization
cost within IBD. This slice corrects measurement integrity; it does not claim
an IBD speedup or measure time to tip.

## Baseline and reproduction

Branch: `agent/worldstream-ibd-20260918`.
HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`.
The checkout already contained staged and unstaged changes, including earlier
`serial_bench` work. Those changes are preserved, not part of this slice.

Baseline `tools/serial_bench.c` SHA-256:
`52957d2f666e4e48c40c2e40bc686784c1886e5d7bc138f4af289afe814f0ac9`.

A two-record fixture containing a complete serialization fixture and `zz`
exited 0 and emitted three throughput rows with `verified=1`, despite dropping
one of its two records. The new regression also fails on the baseline when
the damaged record precedes the valid record: exit 0 instead of refusal.
The complete fixture is deliberately not a consensus-valid block.

## Change and qualification

Within the existing bounded corpus window, nonempty odd-length or nonhex
records now reject the load. Allocation and stream-read failures also reject
partial loads. Loaded buffers are released before returning failure. Empty
lines, CRLF records, and a final record without a newline remain supported.
The existing 4096-block sampling bound is unchanged.

Run after building the standalone tool:

```sh
make serial_bench
bash tools/scripts/serial_bench_partial_corpus_selftest.sh
bash tools/scripts/serial_bench_observation_selftest.sh
bash tools/scripts/serial_bench_topology_selftest.sh
```

Observed locally:

- New CLI regression: 24 refusals, plus complete text and CSV controls passed.
- Existing observation and corpus regressions: 16 refusals and their positive
  controls passed, including the deliberate parity-mismatch control.
- Existing topology regression passed.
- GCC 14 compiled and linked the standalone source list with C23, `-O3`,
  `-march=x86-64-v3`, `-Wall -Wextra -Werror -pedantic`.
- Clang 20 static analysis reported the same two zero-size allocation warnings
  in the baseline and changed sources, in the unchanged txid and timing-sample
  code. No new diagnostic appeared.
- Bash syntax and `git diff --check` passed. The staged diff and unrelated
  tracked working-tree diffs remained byte-identical to their entry snapshots.

The normal make path encountered unavailable Tor setup and read-only Git
metadata. The standalone compiler recipe was run directly instead. The
documented lint driver ran all 32 fast gates: 28 passed. Four failed outside
this slice: pre-existing root entries, complexity violations in other tools,
an unregistered variable in an existing HTTP regression, and a Windows guard
self-test unable to create scratch state outside the permitted workspace.
No lint baseline or acceptance threshold was relaxed.

Only benchmark input handling changes. Consensus sources, validation rules,
node scheduling, database tuning, and optional acceleration behavior are
unchanged. No production node or datadir was used.

## Publication limitation

No commit or push was possible in this session: `.git` is read-only and GitHub
DNS resolution failed. `origin/main` also does not exist on this remote.
The branch remains unchanged; remote SHA equality was not reverified.
