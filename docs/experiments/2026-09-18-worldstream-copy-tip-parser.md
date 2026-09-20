<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream copy-profiler height observer cost

`fold_profile.sh` delegates copy startup and height observation to
`tools/repro_on_copy.sh`. Its `tip()` reader started `sed` and `head` for
every RPC response. The change retains the exact two sed substitutions and
uses POSIX sed branching to quit after the first successful substitution,
removing the second parser process. The existing response-envelope choice,
RPC call count, polling cadence, tip-regression threshold and climb gate
remain unchanged.

Baseline: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The checkout already contains
unrelated staged and unstaged Worldstream changes; `repro_on_copy.sh` was
clean before this slice. Baseline script SHA-256:
`4f3f8714f47e11e84ff1f3f80fea95b47e4b7e3177baeb41618dec2ea875b1a5`.
Updated script SHA-256:
`2ecf8a11fa08b4a6084f4f45be71556967980eeca53c646ea7e85554a4f77d1c`.

Measured on Linux x86_64, AMD EPYC 7402P, GNU sed 4.9, with warm caches
and uncontrolled host load. The fixture stubs RPC, extracts only the real
height reader, and never opens a datadir, starts a node or contacts a peer.
Each timed invocation includes 29 correctness cases, 300 benchmark reads
and three process-count probes. Three alternating baseline/updated pairs:

| Measurement | Baseline | Updated |
|---|---|---|
| External parser processes per read | 2 | 1 |
| Wall seconds per fixture invocation | 1.00, 1.00, 1.00 | 0.98, 0.97, 0.97 |
| User + system CPU seconds | 1.67, 1.67, 1.67 | 1.15, 1.14, 1.14 |

This is observer overhead, not an end-to-end IBD or time-to-tip improvement.
The deterministic regression bound is one external parser per read; timing
is informational. Baseline output checks pass but its process-count gate
fails (six processes for three reads); the updated reader passes both.

Reproduce with `make repro-copy-tip-selftest`, or run without build
prerequisites:

```sh
sh tools/scripts/repro_copy_tip_selftest.sh
time sh tools/scripts/repro_copy_tip_selftest.sh --bench
time sh tools/scripts/repro_copy_tip_selftest.sh --bench /path/to/baseline.sh
```

The 29 cases cover bare and enveloped heights, missing/null/string values,
whitespace, same-line and multiline duplicates, exact key names, envelope
precedence, negative/zero/wide/leading-zero values, and the existing integer
prefix policy. Both sh and Bash pass. An unconditional-quit mutation fails
the multiline fixture. POSIX/Bash syntax, artifact-symmetry and stopwatch
judge selftests, architecture, shell-host assumptions, pipefail-status-pipe,
discarded-status, no-API-keys, no-Python, no-warning-suppression and
`git diff --check` pass. The core seal verifies all 554 files and 80 sections.

`make lint-fast` ran 32 gates and reported four failures: pre-existing
`.agents`/`.codex` root entries, complexity growth in the already-dirty
`tools/bench_fresh_sync.c`, stale flag first-use pointers, and a Windows
acceptance fixture unable to create its sandbox outside writable roots.
The final Make target is appended so it does not shift existing flag
locations; the flag gate still reports 11 stale pointers in prior work.
`make t-fast ONLY=agent_copy_prove` cannot build with missing offline zlib
and OpenSSL inputs and read-only Git submodule configuration. The focused
Make target passes despite the missing zlib preparation diagnostic.

Owned changes are the height reader, its new hermetic fixture, the appended
Make target and this note. No node, consensus, cryptographic, scheduling,
database or optional-acceleration behavior changes. No generated files,
benchmark output, logs, binaries, datadirs or secrets belong to this slice.

Publication remains blocked: `.git` is read-only, `origin/main` is absent
locally, and the origin query fails because GitHub DNS is unavailable.
No commit, push, remote-SHA equality, full-suite success or real-node
time-to-tip result is claimed.
