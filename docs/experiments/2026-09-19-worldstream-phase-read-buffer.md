<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: batch phase-log filesystem reads

The fresh-sync benchmark opens its child's log on each observation. Its
incremental scanner requests 4 KiB at a time; default stdio buffering on this
Linux host incurred one read syscall for each chunk of startup history. A
64 KiB stdio buffer reduces those syscalls without changing the scanner's
4 KiB search boundaries, byte offsets, marker interpretation or early stop.
If buffer configuration fails, the observer logs the refusal and uses default
stdio. The stack buffer remains alive until the stream closes.

Baseline branch: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with existing pending work.
The pre-slice `tools/bench_fresh_sync.c` SHA-256 is
`fa96727985b090831aa132db01c6f03dcc662a0933b1f121674bc8289377d940`;
the changed file is
`4b11cc0bcb5fe6ca41156049187e2bcd4ef077005a85e46a59e40ff233c22008`.
HEAD alone does not reproduce this dirty-tree baseline.

Linux x86_64, GCC 14.2.0, C23 `-O2`, warm filesystem cache, synthetic
64 MiB log with one late milestone and four absent milestones, twenty fresh
scans per run (plus an unchanged-extent observation after each scan):

| Measurement | Before | After |
|---|---:|---:|
| Read syscalls per run, including counter observation | 327,681 | 20,481 |
| Wall seconds, run 1 | 0.527419 | 0.360251 |
| Wall seconds, run 2 | 0.528224 | 0.362271 |
| Wall seconds, run 3 | 0.527318 | 0.364725 |
| Median wall seconds | 0.527419 | 0.362271 |

The measured observer time fell 31%; read syscalls fell about 94%. These are
benchmark-tool costs, not end-to-end IBD or time-to-tip gains. No node, network,
wallet or production datadir participated. The tradeoff is a 64 KiB stack
buffer and up to 64 KiB filesystem read-ahead on an early match; the scanner
still searches only its original 4 KiB chunks and snapshots the log extent.

Reproduce the fixture and optional static analysis:

```bash
bash tools/scripts/bench_fresh_sync_buffer_selftest.sh --analyze
make bench-fresh-sync-selftest
```

The fixture compiles the production opener and scanner. It checks late,
absent and early markers, every marker split at both 4 KiB and 64 KiB
boundaries, unchanged extents, buffer-setup refusal and missing logs. On Linux
it enforces a syscall budget; other platforms retain behavior coverage but
report unavailable syscall counts. Wall time is informational. The saved
baseline at `/tmp/worldstream-phase-buffer/before.c` passes behavior with
`--baseline` and fails the new syscall budget without that flag.

Validation: the full `make bench-fresh-sync-selftest` target passed, as did
the additional startup-interruption and height tests. C23 warnings-as-errors,
GCC static analysis, AddressSanitizer and UndefinedBehaviorSanitizer passed
for the focused fixture. LeakSanitizer cannot run under this environment's
tracing, so the sanitizer rerun disabled leak detection only. Architecture,
shell syntax, pipefail-status, discarded-status, shell-host-assumption,
consensus-parity and core-seal-mirror checks passed. The core seal verifies
all 554 files and 80 sections. `git diff --check` passed.
`make lint-fast` exceeded a 55-second bound during preparation; no full lint
pass or full-node/live-sync acceptance is claimed.

This slice adds seven lines to the benchmark opener, one test registration,
the hermetic regression and this report. Consensus, validation, acceleration
policy and all Hetzner-owned runtime/scheduling/database surfaces are
unchanged. Existing staged changes remain byte-identical. No credentials,
production data, logs, binaries or build output are part of the slice.

Publication remains blocked: `.git` and the existing temporary checkout's
Git metadata are read-only, and origin lookup cannot resolve `github.com`.
No commit, push or remote-SHA equality is claimed. The exact incremental patch
is retained at `/tmp/worldstream-phase-buffer/slice.patch`; it depends on the
pre-existing pending phase-scanner work and must not be applied as if HEAD
alone contained that work.
