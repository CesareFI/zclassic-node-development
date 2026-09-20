<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: make redirected IBD benchmark progress observable

The cold-start benchmark used the default stdout buffering. A supervisor pipe
or redirected file could therefore hide completed startup and phase lines
until the buffer filled or the benchmark exited. This delayed observation of
the current sync stage even when the benchmark had already printed it.

The change configures line buffering before the first stdout write and refuses
setup if that configuration fails. It changes only the standalone benchmark's
output delivery. Consensus, validation, node scheduling, database behavior and
optional acceleration selection are unchanged.

## Reproduction and measurement

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. Host: Linux 6.8.0-139-generic, x86_64,
AMD EPYC 7402P, GCC 14.2.0, glibc stdio. These are local fresh-process pipe/file
fixtures, with no node, peer, chain data, network load or cache-dependent scan.

The regression compiles the production entry-point output setup and banner,
omitting datadir, certificate and node operations. A separate handshake holds
the child alive after the banner. The parent checks visibility before releasing
the child and checks that all output bytes remain intact after exit.

| Observation | Baseline | Line buffered |
| --- | ---: | ---: |
| Pipe bytes visible while child remains alive | 0 / 293 | 293 / 293 |
| Pipe observation wait | 500.484 ms (timeout) | 0.010 ms |
| File bytes visible while child remains alive | 0 / 293 | 293 / 293 |

The time is the parent observation wait after the handshake, not node startup
latency or time-to-tip. The regression asserts visibility and byte preservation,
not a fragile microsecond threshold. No end-to-end IBD speedup is claimed.

```bash
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/bench_fresh_sync.c > /tmp/bench-output-baseline.c
bash tools/scripts/bench_fresh_sync_output_selftest.sh --baseline /tmp/bench-output-baseline.c
bash tools/scripts/bench_fresh_sync_output_selftest.sh --analyze
make bench-fresh-sync-output-selftest
```

The normal assertion fails on the baseline. The new target also runs when
building `bench_fresh_sync`.

## Validation and limits

- Regression passed for pipes and regular files, with C23, `-Wall -Wextra
  -Werror`, and GCC `-fanalyzer`.
- Standalone production binary linked with its existing build flags. Strict
  C23 syntax checking passed. Existing optimized-build warnings remain in
  certificate-copy formatting and unchecked `system` calls outside this slice.
- All 25 existing/current `bench_fresh_sync_*selftest.sh` scripts passed in the
  original Worldstream checkout with this change applied over its prior work.
- Core seal, architecture tree, discarded-status, pipefail-status-pipe,
  no-Python and shell-host-assumptions source checks passed.
- Bash syntax and `git diff --check` passed. The diff contains only benchmark
  source, its fixture, Make wiring and this experiment record.
- Full `make lint` could not finish: missing OpenSSL dependencies could not be
  downloaded because GitHub DNS resolution failed. The shell-host aggregate's
  separate readiness fixture also lacked `jsonq`; its source scanner passed.
  No full-node or live-chain acceptance is claimed.

The original checkout's Git metadata is read-only and contains extensive
unrelated staged work. The isolated slice was prepared in
`/tmp/worldstream-progress-slice` on the same development branch, with the
small source changes also applied to the original working tree. No existing
staged work was included. Fetch/publication require working access to origin;
the observed GitHub DNS failure must not be mistaken for remote verification.
