<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream cold-start seed-readiness log scan

Baseline source: `c1f7863d098e1efaa8deba240c580ae0559312a5`,
`tools/scripts/cold_start_to_tip_probe.sh`, function `note_seed_ready`.
That function was byte-identical to HEAD at session entry; surrounding files
already contained uncommitted work, which this slice preserves. Measurements
use Linux x86_64, AMD EPYC 7402P, Bash 5.2.21, ordinary warm filesystem caches
and ambient host load. No node, network peer or production datadir ran.

In consensus-state-bundle mode, each pending installation poll searched the
entire log separately for the installed marker and the next-boot request
marker. Combining both fixed strings in one `grep -F` invocation halves the
log scans when both are absent. Either marker still yields the same readiness
observation. An existing marker file still bypasses log reads; an already
seeded observer still does no work. Operator and legacy modes are unchanged.

| Twenty pending polls, 16 MiB log without either marker | Before | After |
|---|---:|---:|
| Log scans / grep processes per poll | 2 | 1 |
| Total log bytes scanned | 640 MiB | 320 MiB |
| Wall time | 0.345 s | 0.197 s |
| User CPU | 0.086 s | 0.078 s |
| System CPU | 0.264 s | 0.122 s |

These are observer costs, not measured end-to-end IBD gains. Timing is
informational; the regression asserts scan count and behavior, not a noisy
elapsed-time threshold. A pending poll still scans the whole log once.

Reproduce the local fixture and benchmark:

```bash
bash tools/scripts/cold_start_seed_scan_selftest.sh --bench
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/cold_start_to_tip_probe.sh > /tmp/seed-scan-baseline.sh
bash tools/scripts/cold_start_seed_scan_selftest.sh --bench /tmp/seed-scan-baseline.sh
```

The baseline passes behavior checks and fails the one-scan budget. The test
extracts the actual observer and constants without executing harness setup.
It covers missing/empty logs, either marker, binary data, an unterminated
line, partial/complete appends, truncation, marker-file precedence, one-time
marking and the other bootstrap modes. Removing request-marker recognition
fails the regression. The probe's existing `--selftest` invokes it, so the
existing `mvp-coldstart-to-tip-local` preflight runs it too.

The focused benchmark, full probe selftest, cold-start stopwatch selftest,
artifact-symmetry selftest and five startup-timing cases pass. Shell syntax,
architecture, shell-host-assumption, discarded-status and pipefail-status
checks pass, including a separate discarded-status scan of the new test.
`git diff --check` passes. ShellCheck is unavailable. The node build encountered
read-only Git metadata during Tor submodule setup. The build and full lint
attempts were interrupted during prerequisites; complete build/publication
evidence remains unavailable. No C/compiler semantics change. Consensus,
cryptographic validation, optional acceleration, scheduling, database and
runtime code are untouched. No secrets, logs, binaries or benchmark output
are part of this slice.

Publication is blocked: this environment mounts Git metadata read-only, and
GitHub DNS resolution fails. No commit or push has been made; the branch is
still `agent/worldstream-ibd-20260918`. Existing staged changes are unchanged.
