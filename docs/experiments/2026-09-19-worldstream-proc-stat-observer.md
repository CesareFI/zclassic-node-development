<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream CPU/RSS observation cost

Base commit: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. Linux x86_64, Bash 5.2.21, GNU Awk 5.2.1.
The checkout already contained extensive staged and unstaged Worldstream work.
This slice preserves it and changes only the stopwatch's CPU/RSS observation,
its selftest wiring, and the new regression and this report.

Every resource sample parsed the same captured `/proc/PID/stat` twice, starting
one awk process for CPU ticks and another for RSS pages. The combined reader
splits the record once and returns both values. Each counter independently
retains its `-1` missing-value sentinel. CPU addition, RSS text, the last-closing-
parenthesis rule for process names, and caller unit conversions are unchanged.
The obsolete individual readers are removed.

The regression drives the real resource-sampling function with canned proc
files supplied by a shell fixture. It verifies normal and unusual process
names, zero counters, wide RSS text, truncated/malformed fields, missing
processes, independent counter availability, and conversion to CPU seconds
and RSS KiB. A deterministic process-budget assertion counts actual awk
invocations in the caller. The original implementation passes the value checks
and fails that budget with two invocations; the replacement passes with one.

Three alternating runs of 500 samples, using the same fixed fixture and warm
tool/filesystem caches on this host:

| Measurement | Before | After |
|---|---:|---:|
| External stat parsers per resource sample | 2 | 1 |
| Wall time, run 1 | 8.013 s | 5.564 s |
| Wall time, run 2 | 7.933 s | 5.563 s |
| Wall time, run 3 | 7.925 s | 5.593 s |
| Median wall time | 7.933 s | 5.564 s |

The median fixture cost fell about 30%. This measures resource-observer
overhead, not end-to-end IBD or time-to-tip acceleration. It does not include
real proc filesystem access or RPC. Timing is reported, never used as a pass
threshold. No node, real peer, wallet or production datadir participates.

Reproduce the current regression and benchmark:

```bash
bash tools/scripts/stopwatch_proc_stat_selftest.sh --bench
bash tools/scripts/cold_start_to_tip_stopwatch.sh --selftest
```

For an A/B run, pass a saved pre-change stopwatch script after `--bench`.
The measured pre-change working-tree script had SHA-256
`dda6179dcad2d32c493c6a4cf46f138973a7e6d91875ca18fb57927ede0cd133`;
it includes earlier pending I/O-observer improvements, so the base commit
alone is not the measured baseline. The final measured stopwatch script has
SHA-256 `95d9c13d03f764868d1f16d8a0d3dbad8f83c70026c3b60263dfb4e7ba381f48`.

Validation passed: focused regression, full stopwatch selftest, artifact-
symmetry mutation selftest, Bash syntax checks, architecture-tree gate,
shell-host-assumptions gate, pipefail-status-pipe gate, consensus-parity static
gate, core-seal-root mirror gate, and `git diff --check`. Direct core-seal
verification matches all 554 sealed files and 80 sections. No consensus,
validation, acceleration policy, peer scheduling or database code changed.
The new untracked selftest was checked directly; Git-index-based lint gates
do not yet include it. ShellCheck is unavailable.

Publication remains incomplete. `git fetch origin main` failed because `.git`
is mounted read-only. Remote branch lookup failed because `github.com` did
not resolve. No commit or push was performed, and remote SHA equality was
not independently verified. The public build could not acquire its absent
Tor submodule through the read-only Git metadata and was stopped; full lint
did not complete within its 60-second attempt. The direct focused gates above
passed using the available lint binary, but are not full publication evidence.
Temporary fixtures and benchmark output remain outside the proposed changes.
