<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: retain valid integer observations in sync benchmarks

The cold-start benchmark's `json_get_int()` required a colon immediately
after a field name. A formatted getblockcount reply such as
`{"result" : 1234567}` therefore displayed height -1. Its `atol()` conversion
also reported null as zero, truncated fractional values, and saturated
overflowing values. These failures affect height and background-validation
telemetry used to interpret time-to-tip results.

This slice repairs measurement fidelity; it does not demonstrate faster IBD.
The reader now accepts JSON whitespace around the colon and requires a whole,
in-range integer token followed by an object separator. Invalid observations
retain the existing -1 sentinel. It remains a reader for fixed telemetry
fields, not a general JSON document validator.

## Reproduction and observations

Local fixture execution on Linux x86_64, GCC 14.2.0, C23, `-O2`, without a
running node, network access, chain data, or credentials:

```sh
bash tools/scripts/bench_fresh_sync_integer_selftest.sh /path/to/before.c
bash tools/scripts/bench_fresh_sync_integer_selftest.sh
make bench-fresh-sync-selftest bench-fresh-sync-height-selftest
```

The fixture extracts the production integer reader and tests compact and
formatted fields, a field name also appearing as a string value, absent and
malformed tokens, integer limits, overflow, and stale errno. Before: 18 failed
observations out of 27. After: zero failures out of 27. The existing height
observer still makes one height RPC for 100 stable-state polls, and five height
RPCs across its 116-poll transition fixture. No new RPCs or child processes are
introduced into the observer.

The checkout already contained extensive uncommitted work. Exact source
identities for `tools/bench_fresh_sync.c` in this experiment (SHA-256):

- Before: `4cfc3570e01cc370704e80b8f0a9ebe45e475a5e75211da810d3cf9aeee037b3`
- After: `1821a73e6c50ad6c1d6ad76e5eb9e89394ffd98b6022ba3aca693dcc193a2458`
- Checkout HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`

## Validation and boundaries

The complete benchmark selftest target and height target pass. The new
regression is part of the height target, which also runs when building the
benchmark. The integer, height-demand, and report-demand fixtures pass GCC
`-fanalyzer`; the focused C fixtures compile with C23 `-Wall -Wextra -Werror`
and the shell changes pass `bash -n`. `make bench_fresh_sync` succeeds with
pre-existing warnings about unchecked `system()` results and possible command
string truncation elsewhere in the benchmark.

The consensus seal independently passes for all 554 sealed files and 80
sections. The discarded-status and pipefail-status shell gates pass, as do
worktree and index `git diff --check`. `make lint-fast` did not produce a gate
verdict after several minutes of setup and was interrupted; full lint is
unverified, not passed.

Only benchmark parsing, fixture includes, test registration, and this record
are changed by this slice. Consensus predicates, validation semantics, optional
acceleration, scheduling, databases, and production state are untouched.
No end-to-end sync or sovereign-validation performance claim is made.

Publication is unavailable in this environment: `.git` is mounted read-only,
and `git fetch origin main` fails when opening `.git/FETCH_HEAD`. No commit or
push was performed; the branch remains `agent/worldstream-ibd-20260918`.
