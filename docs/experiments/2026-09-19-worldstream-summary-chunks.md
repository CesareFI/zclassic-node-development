<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: amortize old snapshot-summary reads

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fresh-sync benchmark's display-only snapshot-summary lookup searches at
most the final 16 MiB of its child's log. An absent marker required 1,024
seek/read pairs. Keep the first 16 KiB read, then search older history in
64 KiB chunks: the same absent lookup now needs 257 pairs. Latest-match
selection, overlap retention, binary rejection and the total byte budget
remain unchanged. Recent summaries still need only one 16 KiB read.
Older matches can read up to 48 KiB more surrounding text; the bounded stack
buffer grows by 48 KiB. This is a standalone benchmark, not node runtime.

The baseline is the working source at session entry, SHA-256
`2dcd7df57cad9a2f58d0ca2647009376172d9c97e67d5c11d332c3266844acf7`.
Earlier scanner improvements and other dirty work are prerequisites, not part
of this slice. Temporary baseline, check output and the incremental patch are
under `/tmp/worldstream-summary-chunks/`; none belongs in a commit.

## Measurement

Linux x86_64, GCC 14.2, C23 `-O2`, warm local text fixture and uncontrolled
ambient load. Three repetitions each perform twenty absent-marker lookups on
a 16 MiB file using unbuffered stdio, as the production observer does. Each
repetition reads exactly 335,544,320 bytes in both versions.

| Measurement per twenty lookups | Baseline | Candidate |
|---|---:|---:|
| `fread` calls | 20,480 | 5,140 |
| Kernel read calls including counter observation | 20,481 | 5,141 |
| Wall seconds, repetition 1 | 0.075288 | 0.059596 |
| Wall seconds, repetition 2 | 0.074230 | 0.059038 |
| Wall seconds, repetition 3 | 0.074182 | 0.058943 |

Median fixture time fell about 20%; read calls fell about 75%. Wall time is
descriptive; the regression gates call counts and bytes. No node, peer,
production datadir or validation ran. This is not an end-to-end IBD gain.

## Validation and remaining gaps

`bash tools/scripts/bench_fresh_sync_summary_chunks_selftest.sh --analyze`
passes strict C23 compilation and GCC static analysis, enforces at most 257
reads per full search, checks every marker split at both chunk boundaries,
and preserves the small recent-summary read. The baseline passes behavior
checks with `--baseline` and fails the new call budget without that option.
The regression is wired into `make bench-fresh-sync-selftest`, which passes.
Existing summary tests also pass for latest matches, size boundaries, binary
logs, truncation/refusal, the total scan budget and kernel byte accounting.

Shell syntax, architecture-tree, pipefail-status, discarded-status and
shell-host-assumption checks pass. Whole-file strict compilation fails on
pre-existing ignored `system()` return values and potentially truncated copy
commands; the entry baseline reproduces those failures. `make lint-fast`
exceeds a 60-second bound during initialization, so no aggregate lint pass is
claimed. This slice does not alter consensus, validation, acceleration policy,
peer scheduling, databases or node runtime. Its reviewed source/test/doc diff
contains no secrets, logs, binaries, caches or generated artifacts.

Publication is incomplete. Fetch cannot write `.git/FETCH_HEAD`; a subsequent
index operation cannot create `.git/index.lock`. Staging the new regression
reported success, so it remains staged; no existing staged work was changed.
The remote branch lookup fails because GitHub DNS is unavailable. No commit,
push, current-upstream integration or remote-SHA verification is claimed.
Do not commit the entire dirty Makefile or benchmark as this slice: both
contain earlier work. Aggregate checks and publication remain outstanding.
