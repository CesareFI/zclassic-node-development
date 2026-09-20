<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stop parsing completed fold-profile counters

The fold-profile observer's `jnums1` continued visiting every comma-delimited
field and subsequent line after finding all requested counters. The smallest
change counts newly found output columns, stops the field loop when complete,
and skips parsing later lines. Input still drains to EOF, so the producer does
not acquire an early-exit/SIGPIPE failure. Missing fields still scan the entire
response and retain their zero sentinel. First integer matches, cumulative
versus last-batch ordering, duplicate keys, and wide integer text are unchanged.

This changes external IBD instrumentation only. Consensus, validation,
acceleration policy, runtime scheduling, and database behavior are untouched.

## Baseline and results

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Existing staged and unstaged
Worldstream changes were preserved. The baseline is the working script before
this slice, not clean HEAD. Its SHA-256 is
`56f5fd4935dc7ce0782c8bc17f3ef9f5d389fb8532591e7710bbaca68014cf0b`;
the resulting script's SHA-256 is
`e71d95bc708738cd931a7e8160a2f12ecdbf003ea61af81552b52ff11978bc1e`.

Linux x86_64, AMD EPYC 7402P, dash, GNU Awk 5.2.1. The synthetic response is
10,402 bytes: cumulative stage/counters, 500 diagnostic fields, then last-batch
counters. This is a bounded stress fixture, not a captured node response.
Each timing runs 500 real reader calls in shell subprocesses with warm ordinary
filesystem caches. Ambient host load is uncontrolled; there is no RPC, node,
peer, chain data, or production datadir.

| Measurement | Before | After |
|---|---:|---:|
| Field-loop entries, two response lines | 1,010 | 3 |
| Wall seconds, three 500-read runs | 2.39 / 2.38 / 2.40 | 2.27 / 2.27 / 2.30 |
| Median wall seconds | 2.39 | 2.27 |
| User CPU seconds, three runs | 0.81 / 0.85 / 0.86 | 0.73 / 0.73 / 0.66 |

The approximately 5% median reduction is fixture observer cost, not an
end-to-end IBD or time-to-tip improvement. Process startup still dominates;
the sampler still uses six external parsers per complete sample. Splitting
the first line also remains proportional to that line's size. The regression
asserts work and output, not a noisy wall-clock threshold.

## Reproduction and checks

```sh
sh tools/scripts/fold_profile_scan_selftest.sh --bench
sh tools/scripts/fold_profile_selftest.sh
sh tools/scripts/fold_profile_rpc_selftest.sh
make fold-profile-selftest
```

The new selftest accepts an optional final path to a baseline script. The
baseline passes all seven output fixtures, then fails the three-field work
ceiling with 1,010 visits. The counter is inserted into an extracted copy of
the real field loop; timing uses the uninstrumented reader. Incrementing the
completion count twice per discovered column fails the output regression.

Direct execution of all three selftests passes: legacy/current CSV schemas,
duplicate and missing fields, wide counters, RPC rejection at each of five
endpoints for three failure modes, and recovery. POSIX shell and Bash syntax
checks and `git diff --check` pass. No compiled source changed.

The combined Make target for the selftest, architecture, shell-host and
pipefail gates exceeded a 50-second bound during initialization, after
unchanged template generation and a missing-Tor-archives warning. A separate
`make lint-fast ZCL_LINT_SERIAL=1` attempt also exceeded 50 seconds at that
stage. Those gates are unverified, not passing. Pre-existing staged entries
were preserved.

Owned delta: the reader's completion count, one Makefile selftest line, the
new focused selftest, and this report. Do not commit the other pre-existing
changes in the two modified files as part of this slice. Temporary fixtures,
timing output, and baseline copies are outside the tracked tree.

Publication remains incomplete: fetch cannot write the read-only
`.git/FETCH_HEAD`, and GitHub DNS resolution fails. Staging the two new files
did succeed, but unstaging them was refused because `.git/index.lock` cannot
be created on the read-only filesystem. With integration gates unfinished
and upstream unavailable, no commit or push was made; remote SHA equality is
unverified. The new files are staged; reader and Makefile edits are unstaged.
