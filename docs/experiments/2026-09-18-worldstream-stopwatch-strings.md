<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stopwatch evidence string cost

This slice removes two external text programs per string from the shared
stopwatch emitter. Cold-start phase snapshots and final proof artifacts use
this helper, as do recovery and copy-prove observations. The change preserves
the existing byte transformations, including escaped tabs/carriage returns
and newlines converted to spaces. It does not change evidence acceptance.

## Baseline and measurement

Measured on Linux x86_64, AMD EPYC 7402P 24-Core Processor, Bash 5.2.21,
with ordinary warm filesystem caches and ambient host load. Checkout HEAD was
`c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. The checkout already contained unrelated
staged and unstaged work; the baseline emitter itself matched HEAD.

The workload captures 500 `json_string` results using the same shell command
substitution pattern as its callers, with one fixed 41-byte string containing
quotes, a backslash, a newline and a tab. Timing excludes fixture setup and
byte comparisons. Each timing is one observation, not an SLO claim.

| Implementation | Wall seconds | User seconds | System seconds | External text tools/string |
|---|---:|---:|---:|---:|
| Baseline `sed`/`tr` pipeline | 2.526 | 0.614 | 3.366 | 2 |
| Bash substitutions | 1.091 | 0.314 | 0.878 | 0 |

This is observer overhead, not a measured time-to-tip improvement. Command
substitution still creates shell subprocesses. No real node or network sync
was benchmarked, and long arbitrary payload performance was not measured.

The measured library SHA-256 identities, including pre-existing parser edits:

- Before: `d035040c886b974b1cc44fdae887b5b92cd4a85d1725c37c383a614dfca64fe9`
- After: `1cb92175889700a5a8e8f3633921a1dcee3ec6058b899b9b19698767f9f19f2b`

## Reproduction and validation

Run `make stopwatch-string-selftest ARGS=--bench`. An optional library path
after `--bench` selects a baseline implementation when invoking
`bash tools/scripts/stopwatch_string_selftest.sh` directly. The baseline
passes all byte checks, prints its timing, then fails the process-cost gate.
The updated helper passes with external executables unavailable.

The fixture checks exact output bytes for empty strings, quotes, backslashes,
literal escape sequences, whitespace, UTF-8 and every non-NUL byte value.
A mutation removing backslash escaping fails. A separate library fixture
containing HEAD plus only this function change also passes; this slice does
not depend on the checkout's earlier parser optimizations.

Passing checks: string regression, stopwatch artifact symmetry, stopwatch
evidence judge, cold-start and recovery harness selftests, integer and busy
reader regressions, and all 11 fresh-boot weld fixture assertions. Architecture,
pipefail status, discarded status and shell-host-assumption Make gates pass.
Shell syntax and `git diff --check` pass. The string regression is a prerequisite
of `stopwatch-symmetry-selftest`.

Full `make lint` did not complete: its prerequisite dev build could not download
zlib because GitHub DNS failed, then compilation failed creating a dependency
file through `/proc/self/fd/8`. This is incomplete publication evidence.

## Scope and publication

Owned changes are only `json_escape` in `stopwatch_json_lib.sh`, the new
`stopwatch_string_selftest.sh`, its Make target/dependency, and this note.
Preserve all other existing hunks, including those in the shared library and
Makefile. No consensus, validation, optional acceleration, peer scheduling,
database behavior or node runtime changes. No secrets, production state,
generated files, binaries or raw benchmark output belong in this slice.

Publication is blocked: `.git` is read-only, so the required fetch could not
write `FETCH_HEAD`; `git ls-remote origin` also failed resolving GitHub.
There is no new commit, push or verified remote SHA for this slice. Finish the
full gates and publish only the development branch when those facilities are
available; do not include the checkout's unrelated pending work.
