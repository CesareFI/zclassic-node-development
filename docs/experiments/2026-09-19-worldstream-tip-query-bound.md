<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound repeat-run tip observations

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The repeated C3 time-to-tip driver queried tips with `timeout 20`. A client
ignoring SIGTERM could keep that observation running indefinitely, delaying
the initial peer check, subsequent trials, or the final report. The reader
also returned stdout from failed queries, allowing a plausible tip prefix to
become hash evidence. Add a one-second forced-kill grace and return output
only after command success. Successful queries and the 20-second initial
budget are unchanged; failed observations remain unavailable.

The baseline is the existing working file, SHA-256
`984349793b419516caaed09a23c58c6b44a3fa2f3e6335c7196725b7af6b79f2`,
not pristine HEAD. Earlier changes in this file remain separate. The entry
snapshot and slice patch are under `/tmp/worldstream-tip-query-bound/`.

## Reproduction and measurements

Run `bash tools/scripts/c3_stopwatch_tip_query_selftest.sh [source.sh]`.
The test extracts the actual reader, substitutes an isolated CLI, and shortens
only the query budget from 20 seconds to 100 ms. The one-second forced-kill
grace remains real. No node, network, wallet or production datadir participates.
Host: Linux x86_64, Bash 5.2.21, GNU coreutils timeout 9.4.

| Query | Baseline elapsed / returned bytes | Candidate elapsed / returned bytes |
|---|---:|---:|
| Successful response | 9 ms / 50 | 10 ms / 50 |
| Response followed by exit 7 | 10 ms / 50 | 11 ms / 0 |
| TERM-resistant response then two-second wait | 2014 ms / 50 | 1109 ms / 0 |

The baseline fails three assertions. The candidate preserves successful bytes,
discards failed and timed-out output, and prevents the resistant client from
writing its post-deadline marker. Missing executable and absent datadir cases
also remain unavailable. Timing is reported, not used as a flaky threshold;
the marker proves termination. The real query now requests forced termination
after approximately 21 seconds, subject to OS scheduling. These are observer
measurements, not end-to-end IBD speedup evidence.

## Validation and limits

- The regression is wired into the existing triple-run `--selftest`, which
  passes including six scratch-isolation scenarios.
- `bash tools/scripts/cold_start_to_tip_stopwatch.sh --selftest` passes.
- Shell syntax, discarded-status, pipefail-status and shell-host-assumption
  gates pass. Repository shell gates scan tracked files; the new fixture also
  receives explicit syntax checking and execution. No compiled source changes.
- `git diff --check` passes and the exact slice diff was inspected.
- The architecture check passes through `build/bin/z23-lint
  check-architecture-tree`; its Make wrapper exceeded a 30-second startup
  bound.
- `make lint-fast` exceeded a 50-second bound during initialization; no
  aggregate lint pass is claimed. Public binary construction encountered the
  read-only Git config while initializing Tor and was interrupted. No live
  chain benchmark or public-node acceptance is claimed.

Consensus, independent validation, optional acceleration policy, custody,
Hetzner-owned scheduling and database code are unchanged. The slice contains
only two shell sources and this experiment record; no secrets, logs, caches,
binaries, production state or generated artifacts are included.

Publication is incomplete: `.git` is read-only (fetch cannot create
`FETCH_HEAD`) and GitHub DNS resolution fails. No commit, push, current
upstream integration or remote-SHA verification is claimed. Preserve earlier
dirty work; do not stage the entire existing driver as this slice.
