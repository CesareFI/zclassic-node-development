<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream stopwatch busy-response polling

The shared stopwatch `is_busy_response` reader launched `grep` and a pipeline
for each response. Both the fresh-sync and recovery stopwatches call it while
polling sync progress. A Bash regular expression removes that observer work
while preserving the existing fixed-field, line-local classification. This
helper remains a telemetry reader, not a general JSON parser.

Baseline: working copy of `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including pre-existing integer-reader
changes. The baseline library SHA-256 was
`11d5ada83b5504942141a784696719d1fa7c5d1f0b303be235359139a55649ee`;
the updated library is
`d035040c886b974b1cc44fdae887b5b92cd4a85d1725c37c383a614dfca64fe9`.
Existing staged changes were left byte-for-byte unchanged.

On Linux x86_64, AMD EPYC 7402P, Bash 5.2.21, with ordinary warm caches and
ambient host load, a fixed busy-response fixture measured:

| 1,000 classifications | Before | After |
|---|---:|---:|
| Wall seconds | 2.529 | 0.022 |
| User + system CPU seconds | 3.304 | 0.022 |
| External parser invocations | 1,000 | 0 |

These are observer-overhead measurements, not an end-to-end IBD speedup.
No node, peer, production datadir, or network was used by the fixture.

Reproduce with:

```sh
bash tools/scripts/stopwatch_busy_selftest.sh --bench
```

An optional final library path selects a saved baseline. The baseline passes
all 13 classification cases and fails the no-external-tools assertion. The
updated reader passes both. Cases cover busy/full responses, false/null/string
values, empty input, similar keys, whitespace, multiline documents, split
fields, duplicate keys, and the existing true-prefix behavior. The cold-start
stopwatch's existing `--selftest` now runs this regression too.

Both stopwatch selftests, the integer-reader regression, stopwatch evidence
judge and artifact symmetry selftests pass. Bash syntax, architecture-tree,
pipefail-status-pipe, discarded-status, shell-host-assumptions and
`git diff --check` pass. The core seal verifies all 554 files and 80 sections.
No C source, consensus or validation behavior, acceleration policy, peer
scheduling, database behavior, or live node state changes in this slice.

`make lint-fast` completed with 28/32 gates passing. The failures were stray
root files, a pre-existing C complexity violation, flag-registry first-use
pointers, and the Windows acceptance selftest being unable to create its
scratch directory outside the permitted workspace. These remain publication
blockers; focused passing tests are not a substitute for the full gate.

Publication is blocked independently: `.git` is read-only, so fetching cannot
write `FETCH_HEAD`, and the origin query cannot resolve GitHub. `origin/main`
is absent locally. No integration, commit, push, or verified remote SHA is
claimed. This slice consists only of the busy-reader function change, its new
fixture, one cold-start selftest invocation, and this note; other existing
working-copy edits are outside the slice.
