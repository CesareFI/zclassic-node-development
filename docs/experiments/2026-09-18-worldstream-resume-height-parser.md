<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: resume benchmark height polling

The two-node synchronization/recovery drill started `sed` for every
`getblockcount` response during startup, initial catch-up and resume
measurement. Replace that field extraction with Bash's regular-expression
reader. RPC calls, polling cadence, deadlines, verdicts and acceptance
thresholds are unchanged. No node or consensus source changes are part of
this slice; optional acceleration and independent validation are unchanged.
Hetzner's scheduling, stalled-request recovery and database work are untouched.

## Baseline and measurement

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. The checkout had unrelated staged and
unstaged work; `tools/scripts/netdisrupt_two_node_drill.sh` was clean before
this slice. Hardware: AMD EPYC 7402P, Linux 6.8.0-139-generic x86_64,
Bash 5.2.21. No node was run for this measurement.

The fixture loads only the actual `nd2_blockcount` function and supplies a
fixed 38-byte mock RPC response. Each of 1,000 polls captures and verifies
the height as its production callers do. Ordinary warm filesystem caches and
ambient host load apply. One before/after run gave:

| Cost | Before | After |
|---|---:|---:|
| `sed` processes per poll | 1 | 0 |
| Wall seconds, 1,000 polls | 5.071 | 2.403 |
| User seconds | 1.149 | 0.586 |
| System seconds | 4.960 | 2.026 |

Elapsed time is informational; the regression gates on the process count
and field values. This removes about 2.7 ms per mock poll on this host. It
does not establish an end-to-end IBD or live resume improvement.

## Reproduction and regression

```bash
bash tools/scripts/netdisrupt_height_selftest.sh --bench
bash tools/scripts/netdisrupt_two_node_drill.sh --selftest
```

The first command accepts an optional final path to a baseline drill. With
the original script it passes the field assertions and fails the zero-`sed`
budget. With this change it passes both. The test is also called from the
drill's existing hermetic `--selftest` entry point.

Coverage includes genesis, positive/negative heights, wide integer text,
missing/null/quoted responses, exact key names, duplicate fields,
multiline responses and the previous reader's narrow noncanonical-input
behavior. Differential fixtures compare against the old `sed` expression.
All production callers consume command substitutions; trailing newlines
are not part of the observed contract. A mutation dropping signed-number
support fails the negative-height check.

The drill, cold-start stopwatch and network-disruption stopwatch hermetic
selftests pass, as do Bash syntax validation, `make check-architecture-tree`,
`make check-shell-host-assumptions` and `git diff --check`. Full node
compilation and `make lint` are unavailable because the required OpenSSL
archive cannot be fetched
(GitHub DNS resolution fails). This leaves live two-node acceptance and
compiled-node checks unobserved. No live datadir or service is touched.

Publication is blocked: fetch cannot write `.git/FETCH_HEAD`, and the
slice-only commit cannot create `.git/index.lock` (read-only filesystem).
Staging succeeded, but committing did not. The remote branch lookup also
fails on GitHub DNS resolution, so its current SHA is unverified. These
local measurements are not a claim of a committed or published change.
