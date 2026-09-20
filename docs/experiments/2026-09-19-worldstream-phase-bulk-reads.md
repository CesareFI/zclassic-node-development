<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: batch phase-log scanner work

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The cold-start benchmark's phase scanner processed large startup backlogs in
4 KiB chunks even when its caller supplied a 64 KiB stdio buffer. This slice
keeps the first two 4 KiB reads in each poll, then uses 64 KiB chunks. The
16 MiB per-poll limit, exact cursor, marker overlap, and small-append behavior
remain. Beyond the first 8 KiB, completion can read up to the next 64 KiB
chunk boundary. Scanner stack storage increases by 60 KiB in this standalone
benchmark process; no node thread is affected.

The baseline is the working source at entry, not pristine HEAD: SHA-256
`e5485aa03fb24b65fa58d2ff50ccc44848b50a0ddb54c4153e332536a119561e`.
Earlier staged, unstaged and untracked work is preserved. This slice changes
only the scanner and its caller's comment, adds bulk-read and split-marker
checks to `bench_fresh_sync_complete_log_selftest.sh`, and tightens the
existing `bench_fresh_sync_selftest.sh` read-count assertion from 4096 to 258.
Both scripts already belonged to the benchmark selftest Make target at entry.

## Measurements

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, `-O2`, synthetic temporary logs,
warm filesystem cache, uncontrolled ambient load. No node, network, credentials,
chain data or production datadir was used. These measure observer overhead,
not end-to-end IBD or time to tip.

| Workload | Baseline | Candidate |
|---|---:|---:|
| Reader calls, ten complete 32 MiB scans | 81,920 | 5,160 |
| Same scans, absent milestone, seconds | .110158 / .108743 / .109211 | .052338 / .053764 / .051631 |
| Same scans, final milestone at EOF, seconds | .107105 / .108501 / .110630 | .052801 / .053447 / .042657 |
| Early complete milestones, bytes over ten scans | 40,960 | 40,960 |
| Final milestone across first 4 KiB boundary, bytes over ten scans | 81,920 | 81,920 |
| Actual opener with 64 KiB stdio buffer, twenty 64 MiB scans, seconds | .327139 / .325728 / .326052 | .317585 / .316191 / .319696 |
| Actual opener, kernel read calls for those scans | 20,481 | 20,481 |

The scanner-only fixture uses default stdio buffering: its median improvement
is about 52%. The actual opener already amortizes kernel reads; its measured
median improvement is about 3%, with no syscall reduction. The deterministic
regression concerns library/scanner work (94% fewer reader calls), not a wall
time threshold. Runs of the scanner fixture alternated baseline and candidate;
the actual-opener candidate runs preceded the baseline runs. Small timing
differences should not be treated as an independently reproduced speed claim.

## Validation

The saved baseline passes value/marker fixtures in measurement mode and fails
the new bulk-read budget in assertion mode. Candidate checks cover every split
of all five markers at the 8 KiB transition and following 64 KiB boundary.
Existing early-completion byte assertions remain unchanged.

Passed the following isolated benchmark selftests (prefix
`tools/scripts/bench_fresh_sync_`, suffix `_selftest.sh`):
`complete_log`, `scan_budget`, `small_append`, `tail_position`, `idle_log`,
`nul_scan`, `buffer`, `growth_io`, `binary_log`, `cadence`, `poll_budget`,
`poll_interrupt`, `poll_wake`, `unavailable_rpc`, `outcome`, `report_demand`,
and the main `bench_fresh_sync_selftest.sh`.

`complete_log --analyze` and `scan_budget --analyze` pass C23 compilation with
`-Wall -Wextra -Werror` and GCC static analysis of the actual extracted scanner.
The full tool builds using the Make target's compiler recipe. Full-tool strict
`-Werror` compilation fails on five ignored `system()` results and two possible
copy-command truncations; the saved baseline reproduces all seven diagnostics.
No warning suppression or unrelated repair was added.

Shell syntax, architecture-tree, pipefail-status, discarded-status and
`git diff --check` pass. `make lint-fast` exceeded a 50-second bound during
initialization; aggregate lint is incomplete. No live-chain acceptance or
public-node build is claimed (the public binary is absent).

Consensus core, reducer, validation semantics, optional acceleration policy,
and Hetzner-owned runtime/scheduling/database code are unchanged. The reviewed
slice contains only source, tests and this record; temporary outputs and the
entry-relative patch are under `/tmp/worldstream-phase-bulk/`.

Publication remains blocked: fetching cannot write `.git/FETCH_HEAD` on the
read-only filesystem, and the remote lookup cannot resolve GitHub. No commit,
push, integration with current upstream, or remote-SHA verification is claimed.
Do not stage these entire dirty files as this slice: they contain prior work,
including the previously untracked main scanner selftest.
