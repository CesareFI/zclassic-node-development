<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound phase-log work between IBD observations

Branch: `agent/worldstream-ibd-20260918`; base HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The cold-start benchmark's incremental phase reader bounded itself to the
file size at poll entry, but consumed the entire unread history in one turn.
An arbitrarily large startup log could therefore delay the next RPC, child
status and benchmark-deadline observation. This slice caps scanner input at
16 MiB per poll. The cursor and partial marker remain available to subsequent
polls; no bytes are skipped. Identity/truncation checks and the early stop
after all milestones remain intact.

This bounds bytes processed, not filesystem latency: an individual blocking
read can still stall. Backlogged phase timestamps remain observation times,
and may be later than before. At the existing two-second polling cadence the
scanner can catch up at approximately 8 MiB/s before other observer costs;
a faster sustained log writer can outpace it. This is a responsiveness bound,
not a reduction in total scan work or a measured end-to-end IBD speedup.

## Baseline and measurement

Existing staged, unstaged and untracked work was preserved. The baseline is
the working source at entry, not clean HEAD. Its SHA-256 is
`3393cce46439f66a996df46524b3eb00dd49f5acfa1a966558ccece1479f408e`.
The resulting source SHA-256 is
`ecd81edf829e51874f4a8f714b78e0ff52a0dc021e9775b7f53731bf790b3926`.

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, C23 with `-O2`. The fixture is a
64 MiB local text log without phase markers, just written and therefore warm
in ordinary filesystem cache. Three sequential baseline observations precede
three candidate observations; ambient load is uncontrolled. No node, network,
RPC, chain data, or production datadir participates.

| First poll | Baseline | Candidate |
|---|---:|---:|
| Scanner input bytes | 67,108,864 | 16,777,216 |
| Wall seconds, three runs | 0.017720 / 0.016524 / 0.016476 | 0.004484 / 0.004176 / 0.004196 |
| Polls to consume all 64 MiB | 1 | 4 |

The regression rejects the baseline on the 16 MiB work ceiling. Candidate
polls consume the exact original extent with no rereads, then read zero bytes
when idle. It also checks each phase marker across the budget boundary with
short and long partial prefixes, and truncation between budgeted turns.

## Validation and owned delta

```sh
bash tools/scripts/bench_fresh_sync_scan_budget_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_buffer_selftest.sh
bash tools/scripts/bench_fresh_sync_complete_log_selftest.sh --analyze
```

The new regression compiles the actual scanner under C23 with `-Wall -Wextra
-Werror -pedantic`; GCC `-fanalyzer` passes. Existing large-history tests now
drain successive turns while retaining their original exact total-byte,
read-syscall, late-marker and absent-marker assertions. Their acceptance
thresholds were not relaxed.

Broader direct benchmark fixtures pass for binary log normalization, read and
poll boundaries, idle log polling, startup, cookies, RPC rejection, interrupted
waits, cadence, readiness, HTTP deadlines, page sizes, timing, tip grace,
incomplete outcomes, report demand, cleanup, integer observations and progress
output. Bash syntax, architecture-tree, shell-host-assumptions, pipefail-status,
discarded-status and `git diff --check` pass.

The aggregate `make bench-fresh-sync-selftest lint-fast
check-architecture-tree` attempt exceeded 50 seconds during initialization;
aggregate acceptance and lint-fast remain unverified. Full benchmark strict
compilation fails on pre-existing ignored `system` results and potentially
truncated copy commands; compiling the saved baseline reproduces the same
seven errors. Full-file static analysis is likewise blocked by the two copy
command warnings. Those failures were not suppressed. The changed scanner
itself passes the strict compiler and analyzer checks above.

Owned changes: the seven-line phase-reader bound in `tools/bench_fresh_sync.c`,
the new scan-budget selftest and its Makefile registration, drain-loop updates
to the buffer and complete-log selftests, and this report. Temporary baseline
copies, compiler output and the isolated delta are under
`/tmp/worldstream-phase-budget/`. Other changes in these already-dirty files
are prerequisites or unrelated work, not authored by this slice.

The delta touches only benchmark instrumentation and its tests. Consensus,
cryptographic validation, optional acceleration policy, and Hetzner-owned peer
scheduling, database and runtime behavior are unchanged. The slice contains
no secrets, credentials, logs, binaries, caches or generated build output.

Publication remains incomplete. Fetch cannot write `.git/FETCH_HEAD` because
Git metadata is read-only, and the remote branch lookup cannot resolve
`github.com`. No commit, push, upstream integration or remote-SHA equality is
claimed. The aggregate checks and full-file compiler failures also prevent
declaring this slice ready for publication.
