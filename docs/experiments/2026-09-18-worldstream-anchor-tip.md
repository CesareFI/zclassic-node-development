<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream anchor-copy height polling cost

The pre-reset probe in `tools/scripts/anchor-snapshot-copy-prove.sh`
starts `sed` and `head` for each height observation. A single POSIX sed
program now exits after its first successful substitution. The regular
expression, first matching line, last numeric occurrence within that line,
one RPC per observation, 60-second probe window, polling cadence and
acceptance gates remain unchanged.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The harness was clean before
this slice; the substantial pre-existing staged and unstaged work is separate.
Baseline harness SHA-256:
`b84dfdc6ab3dd357465f86e37b14ba004586bd42a6f3a8a1c6d5cddcf8072b4f`.
Updated harness SHA-256:
`fd64ef0c7bb3ce975ffb8f7f87f780d036c66c8522292d707a2438ec434a82e0`.

The hermetic test extracts only the actual height reader and stubs RPC.
It never starts a node, copies a datadir or contacts a peer. On Linux x86_64
with GNU sed 4.9, warm caches and uncontrolled host load, three alternating
baseline/updated invocations measured:

| Measurement | Baseline | Updated |
|---|---|---|
| External parser launches per observation | 2 | 1 |
| Wall seconds | 0.98, 0.98, 0.97 | 0.93, 0.94, 0.94 |
| User + system CPU seconds | 1.63, 1.64, 1.61 | 1.10, 1.10, 1.11 |

Each timed invocation includes 21 response cases, 300 benchmark observations
and three process-count probes. The baseline passes all response cases but
fails the new process-count bound (six launches instead of three). Timings
are informational; the regression gate checks parser launches and output.
This is an observer-cost measurement, not an end-to-end IBD speedup or a
real-chain time-to-tip result.

Reproduce without node build prerequisites:

```sh
sh tools/scripts/anchor_tip_selftest.sh
bash tools/scripts/anchor_tip_selftest.sh
/usr/bin/time sh tools/scripts/anchor_tip_selftest.sh --bench
/usr/bin/time sh tools/scripts/anchor_tip_selftest.sh --bench /path/to/baseline.sh
```

The cases pin positive, negative, zero, wide and leading-zero values;
whitespace; same-line and multiline duplicates; later matching lines;
similar keys; missing/null/string/bare values; and the existing line-local
integer-prefix policy. They do not claim general JSON validation. Removing
the conditional branch from the replacement parser makes the fixture fail.
Both sh and Bash pass the fixture and syntax checks. The harness dry-run
leaves its absent fixture directory absent. Import-copy-prove driver tests,
stopwatch artifact-symmetry tests and stopwatch evidence-judge tests pass.
Architecture, shell-host assumptions, pipefail-status-pipe, discarded-status,
no-API-keys, no-Python and `git diff --check` pass. The core seal verifies
all 554 files and 80 sections; no tracked core file differs from HEAD.

The `make lint-fast` and combined Make checks were interrupted after stalling
in preparation. As an alternative, the repository's `run_lint.sh` ran all
32 gates extracted from `LINT_FAST_GATES` against the existing lint tools:
29 passed, including the Windows platform seam. Three failed on surfaces
outside this slice: `.agents`/`.codex` root entries, 21 stale flag first-use
pointers in other files, and the Windows acceptance fixture attempting to
create scratch outside the permitted writable roots. This does not claim
a successful Make build or a fully green integration gate.

Only the anchor-copy harness, its standalone selftest and this note belong
to this slice. No consensus, validation, cryptographic, peer scheduling,
database, optional-acceleration or node runtime code changes. Benchmark
outputs remain under `/tmp`, outside the proposed commit.

Publication is blocked by the execution environment: staging fails because
`.git/index.lock` is on a read-only filesystem; fetching the development
branch likewise cannot write `.git/FETCH_HEAD`; remote queries fail because
GitHub DNS is unavailable. No commit, push or remote-SHA verification is
claimed. The branch remains unchanged, and unrelated staged work is preserved.
