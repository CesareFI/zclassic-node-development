<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bounded phase-log normalization

This slice changes only the fresh-sync benchmark observer and its existing
regression. It changes no consensus, cryptography, validation, node scheduling,
database, or acceleration policy. Independent ZClassic validation remains
authoritative. Measurements below describe synthetic observer cost, not a
measured reduction in end-to-end IBD or time to tip.

## Baseline and change

Branch: `agent/worldstream-ibd-20260918`.
HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`.
The checkout already contained extensive staged, unstaged and untracked work.
Baseline working-tree `tools/bench_fresh_sync.c` SHA-256:
`98092e2897bab3031ee6ad41dda4b278dee861225a614ff83208bd5d8fa3be4a`.
Changed source SHA-256:
`adf55529bab5bb5dbde89e6f3fd609e0b622d00d0f09b6fbabc39e9262b7d3ac`.

`phase_log_normalize` replaces embedded NULs with newlines before searching
for phase markers. Its variable-length scalar loop costs substantially more
on dense or regularly spaced NULs than on ordinary text. The change exposes
the existing full 64-byte window as a fixed-count loop, retaining the bounded
scalar suffix. GCC 14.2.0 at `-O2` reports 16-byte vectorization. No intrinsics,
new architecture flags, wider reads, allocation or dependencies are added.

Linux x86_64, GCC 14.2.0, C23, `-O2`; warm temporary files, ambient host load.
Three sequential baseline/changed pairs were run after other validation ended.
Each observation scans a 16 MiB fixture twenty times and checks the real marker
at its end. Median wall times:

| Input | Baseline | Changed |
|---|---:|---:|
| Text | 129.312 ms | 128.348 ms |
| One NUL per 4 KiB | 133.502 ms | 129.223 ms |
| Dense NULs | 237.173 ms | 145.341 ms |
| Paired sparse NULs | 139.373 ms | 130.198 ms |
| NUL every 65 bytes within each block | 450.102 ms | 168.288 ms |
| Alternating NUL/text | 358.625 ms | 146.292 ms |

Dense input takes 39% less observer time; regularly spaced input takes 63%
less. Normal text is essentially unchanged. Timing is descriptive, never a
machine-dependent acceptance threshold. NUL-heavy fixtures are stress cases;
their frequency in real IBD logs was not measured.

## Reproduction and validation

```sh
bash tools/scripts/bench_fresh_sync_nul_scan_selftest.sh /tmp/worldstream-normalize-window/before.c
bash tools/scripts/bench_fresh_sync_nul_scan_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_binary_log_selftest.sh --analyze
make bench-fresh-sync-selftest bench_fresh_sync
```

The baseline command needs the saved pre-change source. The existing test
accepts any source path. Its added checks compare every byte, including guards,
at all 64 alignments with mixed high-bit bytes and short suffixes. Two new
benchmark shapes exercise full windows separated by text and alternating
NUL/text. Both baseline and changed code pass the same behavioral assertions.
The existing suite already invokes this test; no build wiring was added.

Focused tests, GCC analysis, strict C23 syntax/warnings, shell syntax, the
complete benchmark suite/build, and staged/unstaged whitespace checks pass.
The standalone build still emits warnings in unchanged `system` and copy-path
code. No warning suppression or acceptance threshold was changed.

`make lint-fast` timed out after 45 seconds in prerequisites. Running its 32
gates through the existing lint runner completed: 28 pass, four fail on root
`.agents`/`.codex` entries, existing benchmark complexity, stale flag pointers,
and denied Windows-test scratch access. The changed normalization helper is
not among complexity violations. Aggregate lint and publication are not green.
The architecture gate passes. Exact incremental diffs were inspected; unrelated
tracked diffs and the entire staged diff remain byte-identical to entry.
No core or reducer diff exists. This slice includes no secrets or generated
artifacts; temporary measurements and review patches stay outside the tree.

## Publication

Fetch failed because `.git/FETCH_HEAD` is on a read-only filesystem. Origin
branch queries failed because GitHub DNS is unavailable. No commit or push
was made, and remote SHA equality cannot be claimed. The branch and HEAD remain
as above. This slice must be isolated from prior work and pass integration
before publication. Saved baseline bytes, exact incremental patches and
validation output are under `/tmp/worldstream-normalize-window`.
