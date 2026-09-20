<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: refuse startup observations after the budget

The fresh-sync benchmark accepted an RPC cookie observed after its 300-second
startup budget. `wait_for_cookie` tested readability before checking elapsed
time, then performed another lookup after leaving the loop. Reading a cookie
could also cross the deadline without rejecting the startup observation.
Under scheduling or filesystem delays this admitted an expired trial into the
RPC measurement phase. This is a measurement-integrity defect; no end-to-end
IBD speedup is claimed.

The baseline is the existing dirty working tree on
`agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, not a clean commit.
The source SHA-256 before this slice was
`c823b3c7e2a66027bd0773aa210bddf038f1d4130d56e5f8813c39681b2f4845`;
afterwards it is
`52e7c7f1465246cb367c5e4b2c2109d0b4a3d5df1a2e870b253a6135f6483ba9`.
Existing unrelated changes were preserved.

The isolated C23 fixture uses the actual startup function with a deterministic
microsecond clock, a simulated child, and an inert temporary cookie. It needs
no node, network, production datadir, or real credentials. On Linux x86_64
with GCC 14.2.0:

| Observation | Baseline | Fixed |
|---|---|---|
| Cookie at 0, 299.5, or exactly 300 seconds | Accept all three | Accept all three |
| Wake delayed to 300.000001 seconds | Accept | Refuse before cookie open |
| Readability lookup finishes at 300.000001 seconds | Accept | Refuse before cookie open |
| Cookie read finishes at 300.000001 seconds | Accept | Refuse after read |
| Absent at 300 seconds, available only on another lookup | Accept | Refuse without another lookup |

Late admissions fell from 4/4 to 0/4. The regression fails on the saved
baseline without `--baseline`. The fix timestamps completed observations,
retains the inclusive deadline, reuses the observed readiness result, and
checks elapsed time after the cookie read. It does not make filesystem calls
interruptible or claim that a stalled filesystem operation returns by 300
seconds.

Reproduce with:

```sh
bash tools/scripts/bench_fresh_sync_startup_late_selftest.sh --baseline /path/to/baseline.c
bash tools/scripts/bench_fresh_sync_startup_late_selftest.sh --analyze
make -j2 bench-fresh-sync-selftest
```

The new regression and existing startup/interrupt regressions passed with
GCC analysis and `-Werror`; the full benchmark selftest target passed. The
normal `make build/bin/bench_fresh_sync` target built successfully. Strict
whole-file `-Wall -Wextra -Werror` compilation reports the same existing five
ignored `system` results and two copy-command truncation warnings in both
baseline and modified sources. Shell syntax and Git whitespace checks passed.
The architecture checker passed when invoked directly. The `make` architecture
invocation and full `make lint` did not finish within their 60-second bounds;
full lint and publication evidence remain incomplete.

Only benchmark code, its regression registration, the regression, and this
record belong to the slice. Consensus, validation, acceleration policy,
legacy peer scheduling, database tuning, and node runtime are unchanged.
No logs, binaries, credentials, or benchmark output belong in its commit.

Publication is unavailable in this environment: `.git` is read-only, and
`git ls-remote origin` cannot resolve GitHub. The public node build also
cannot register its required Tor submodule against read-only Git metadata.
This slice is not committed or published, and no remote SHA is verified.
