<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# C3 time-to-tip polling: height extraction cost

Worldstream scope: benchmark observation overhead only. The node, consensus,
validation, optional acceleration settings, peer/request scheduling and databases
are unchanged. No live node, production datadir or external peer was used.

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. This checkout already contained extensive
staged and unstaged work. This slice adds only `parse_tip_heights`, its polling
call and builtin predicates, its self-test invocation, the new
`cold_start_tip_heights_selftest.sh`, and this record. Earlier edits in
`cold_start_to_tip_probe.sh` are excluded from the isolated candidate.

The old observer spawned two sed and two grep processes per successful poll.
It missed whitespace-formatted replies and truncated decimal, exponent and
invalid suffix values into heights, potentially reporting a false captured tip.
The replacement reads the two fixed getblockchaininfo fields with Bash regexes
and requires complete integer tokens. It clears both outputs each time. The
existing acceptance remains: nonnegative blocks and headers, both at least the
captured peer tip, with blocks equal to headers. This is a fixed-field observer,
not a general JSON validator; nested arbitrary JSON is outside its contract.

## Reproduction and measurement

The regression extracts the actual polling body and parser from the specified
source file. It doubles RPC, readiness and seed notifications; it never starts
a node. Fifteen cases cover compact/pretty replies, below/above tip, unequal
heights, genesis, negative/missing/null/quoted values, decimal/exponent/suffix
rejection and similarly prefixed keys. The original fails formatting, invalid
numeric-token and external-process assertions; the candidate passes.

```bash
bash tools/scripts/cold_start_tip_heights_selftest.sh
bash tools/scripts/cold_start_tip_heights_selftest.sh /path/to/probe.sh --bench
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
```

Measured on Linux x86_64, kernel 6.8.0-139-generic, Bash 5.2.21, 48 reported
logical CPUs. Three alternating warm local runs, 200 compact successful polls
each, no network or chain data. Both exact HEAD and isolated candidate include
the same RPC double. Wrappers count sed/grep launches; wall times include that
instrumentation, script sourcing and polling decisions. CPU model, exclusive
host load, cold cache and actual IBD duration were not measured.

| Source | Wall seconds, three runs | External text tools per 200 polls |
|---|---|---:|
| Exact HEAD | 4.041, 4.029, 4.010 | 800 |
| Isolated candidate | 0.320, 0.325, 0.319 | 0 |

Median fixture cost fell about 12.6x. This is not evidence of an end-to-end IBD
speedup; the real probe normally samples every five seconds.

## Validation and publication state

Passed: all 15 polling cases; the C3 probe self-test against both the working
tree and a candidate containing only this slice over HEAD; two-node peer-tip
self-test; stopwatch JSON self-test (15 checks); Bash syntax checks;
`check_pipefail_status_pipe.sh`; `check_shell_host_assumptions.sh`;
`git diff --check`. The pre-existing index patch remained byte-identical.

`make -j2 z23` hit read-only `.git/config` during Tor submodule setup and did
not complete. `make -j2 lint-fast` also did not complete; both were interrupted.
No full build, registered C suite or full lint success is claimed.

Publication is blocked: staging the isolated patch through a temporary index
failed to create Git objects because `.git` is read-only. No commit or push was
made. The branch fetch succeeded once, but subsequent direct remote SHA lookup
failed DNS resolution. No exact remote publication SHA is claimed. Generated
build files and temporary measurement output are excluded from this slice.
