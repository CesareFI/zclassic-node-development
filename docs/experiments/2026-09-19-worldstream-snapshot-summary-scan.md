<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream snapshot-summary observer cost

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The baseline is the working
benchmark at session entry, including previous uncommitted Worldstream work.
Measurements use Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, C23 `-O2`,
warm local file caches and uncontrolled ambient host load. No node, chain,
network or production datadir participates.

When the snapshot-complete milestone appears, `bench_fresh_sync` reads the
last `UTXOs in` diagnostic using `grep | tail`. This scans all prior log
history and starts a shell pipeline inside the timing loop. The new reader
searches backward in 16 KiB chunks with marker overlap, then reads a small
window to recover the complete matching line. It snapshots the file extent,
uses bounded memory, and never presents an oversized or failed read as a
partial summary. NUL-containing scanned chunks yield no text diagnostic.
This diagnostic is not an acceptance or validation predicate.

The regression compiles the actual production reader and its call site.
A 64 MiB text log ending with a summary and one later noise line gives:

| Observation | Before | After |
|---|---:|---:|
| Median seconds, ten reads (three runs) | 0.206188 | 0.000172 |
| Shell pipeline launches, ten reads | 10 | 0 |
| Native log bytes read, ten reads | Not counted in child grep | 166,570 |
| Absent summary, one full-log read, seconds | 0.019328 | 0.024179 |

The absent-summary case still scans the full extent and was about 5 ms slower
in this sample; the optimization benefits the expected near-end summary.
Timings are descriptive, not test thresholds. The regression gates zero
pipeline launches and at most 16 KiB plus 512 bytes per near-end observation.
Baseline `fread` counters measure the pipeline output only, not grep's input.
These results measure observer overhead, not end-to-end IBD speedup.

Reproduction with an entry-state source copy:

```bash
bash tools/scripts/bench_fresh_sync_summary_selftest.sh --baseline /tmp/before.c
bash tools/scripts/bench_fresh_sync_summary_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_summary_selftest.sh /tmp/before.c
```

The last command must fail the work budget. Behavior assertions cover empty
and missing files, missing markers, latest-match selection, CRLF,
unterminated lines, split markers, long nonmatching suffixes, binary chunks,
254-byte accepted and oversized rejected lines, no fallback to an older
summary, and failures during both search and line recovery.

Validation:

- New test passes C23 `-Wall -Wextra -Werror -pedantic`, GCC `-fanalyzer`,
  AddressSanitizer and UndefinedBehaviorSanitizer. Leak checking is explicitly
  disabled for this environment's tracing restriction.
- All sixteen fresh-sync fixture scripts were run: fifteen pass; the existing
  timing fixture still expects 21 seconds where the loop returns 19 seconds.
  Baseline and changed failures match after normalizing extracted line numbers.
  Timing and outcome fixtures only gain a stub for the new diagnostic reader;
  no acceptance assertion changes.
- Both complete benchmark executables compile. Warnings match after source
  path and line-number normalization; no new warning is introduced.
- New functions satisfy the complexity cap. The existing `phase_log_poll`
  violation and `main` baseline violation remain; no baseline is weakened.
- Direct architecture, discarded-status, pipefail-status and shell-host checks
  pass. Shell syntax and `git diff --check` pass. Tracked-tree shell gates do
  not cover the new untracked test; its syntax and C checks run separately.
- `make bench-fresh-sync-selftest` and `make lint-fast` each time out after
  45 seconds during initialization. Full integration acceptance is incomplete.

Source SHA-256:

- Before: `8e40155cd3b085f86013fdf18fc43c9b24814cd2dc715cb3e2c950b3fabafcf6`.
- After: `76d6970e46791330d480e9630713ac8090bb7e32fba7a89e77d587695286b3f5`.

Owned changes are the summary reader and call site, one Make test invocation,
one new regression, two fixture stubs, and this note. All earlier pending
work is preserved. Consensus, independent validation, optional acceleration,
peer scheduling, database behavior and other Hetzner-owned runtime work are
unchanged. No secrets, logs, binaries or temporary outputs belong to this slice.

Publication is incomplete. Git metadata is read-only, so fetch cannot write
`FETCH_HEAD`; the local `origin/main` ref is absent. `git ls-remote origin`
also fails GitHub DNS resolution. No commit, push or remote SHA verification
is claimed. Publication requires writable metadata, origin access, separation
from prior pending edits, and completion of the outstanding integration gates.
