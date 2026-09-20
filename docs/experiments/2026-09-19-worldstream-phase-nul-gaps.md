<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: skip text gaps during phase-log normalization

Owned surface: the standalone fresh-sync benchmark's phase observer,
`tools/bench_fresh_sync.c`, one fixture script and its existing Makefile
selftest target. No node-runtime, peer-scheduling or database change.

The checkout started on `agent/worldstream-ibd-20260918` at
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with substantial staged and
unstaged work. This experiment compares against the working file captured
before this slice, not against clean HEAD. Its SHA-256 was
`8453e58b0ba63f0d3f95756ac950f8f85d100a9a8b44faed2462f4b49d37cf92`.
The resulting C file's SHA-256 is
`fa96727985b090831aa132db01c6f03dcc662a0933b1f121674bc8289377d940`.

The observer already scanned appended bytes in bounded chunks. However,
one NUL near the beginning of a chunk made normalization walk the entire
remaining chunk byte by byte. NULs are normalized to newlines so they
cannot hide later markers or concatenate marker fragments.

Normalization now searches text gaps with `memchr`, visits a short window
around each match, and falls back to one suffix walk when the next window
also begins with NUL. Dense input therefore avoids a search call per byte.
The helper keeps both normalization and the phase reader below the existing
complexity ceiling. No ceiling or baseline was relaxed.

## Measurement

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, `-std=c23 -O2`, ordinary warm
filesystem caches and ambient host load. A temporary 16 MiB fixture has one
real milestone at its end and four absent milestones, requiring a full scan.
Each timing covers twenty fresh scans, excluding compilation and fixture
creation. There is no network, node, wallet or production datadir involved.

Three alternating baseline/candidate runs before helper extraction gave
these median wall times:

| Input | Baseline | Candidate |
|---|---:|---:|
| Text only | 0.129126 s | 0.128929 s |
| One NUL per 4096 bytes | 0.329228 s | 0.133507 s |
| All NUL padding | 0.230150 s | 0.231868 s |

After helper extraction, a confirming run measured 0.128690 s, 0.132663 s
and 0.229803 s respectively. Sparse-NUL scanning is about 59% faster;
text and dense timing differences are within roughly 1%. Timing is
informational, not a flaky wall-clock pass threshold. This is a synthetic
observer-cost result, not a measured end-to-end IBD or time-to-tip gain.
The prevalence of such log input in real IBD remains unmeasured.

Reproduce with:

```sh
bash tools/scripts/bench_fresh_sync_nul_scan_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_binary_log_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_selftest.sh
```

The new fixture accepts an optional final C source path for baseline
comparison. It compiles the actual scanner and requires the full extent and
exact milestone set. Existing binary regressions exercise every byte value,
every NUL offset in a chunk, read-boundary splits and false concatenation.

## Validation and remaining blockers

The focused fixtures pass with warnings as errors and GCC static analysis.
The binary regression passes AddressSanitizer and UndefinedBehaviorSanitizer;
LeakSanitizer is unavailable under this environment's tracing, so that rerun
used `ASAN_OPTIONS=detect_leaks=0` and makes no leak-check claim.
Architecture, shell syntax, pipefail-status, discarded-status and shell-host
checks pass. Both staged and unstaged `git diff --check` pass.

The full benchmark selftest recipe has a pre-existing timing-fixture failure:
it expects `t_done == 21`, but both the saved baseline and candidate return
19. The assertion was preserved. The other recipe tests pass when invoked
directly, including the tests after that failure. The height-demand fixture
also passes. The Make invocations for the aggregate and full lint were
interrupted after remaining in preparation without test/gate results; their
recipes were checked directly where applicable. Full lint is not green.
The complexity gate still rejects the existing `main` value of 60 against
its pin of 55; the modified scanner and new helper do not violate the gate.
Strict whole-file compilation also rejects existing unchecked `system()`
calls and path-truncation warnings, reproduced on the saved baseline.
Linking with the existing benchmark recipe flags succeeds with those warnings.

Consensus, cryptographic and transaction validation, bootstrap authority and
optional acceleration behavior are unchanged. The exact slice contains only
source, the test recipe and this experiment report; temporary outputs and
executables remain outside it. Existing dirty work was preserved.

Publication remains blocked: `.git` is read-only, and a separate remote
read failed because `github.com` could not resolve. No commit or push was
made and no remote SHA equality is claimed. The branch remains unchanged.
