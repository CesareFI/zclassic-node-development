<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream standalone benchmark profile selection

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Measurements use the existing
dirty working tree, including its pending standalone bootstrap allowlist and
benchmark regressions. This is not evidence for the clean HEAD. The slice
adds five Makefile lines, extends `bench_sync_bootstrap_selftest.sh`, and
adds this note. Earlier work is preserved.

## Bottleneck and change

The standalone fresh-sync driver and its regression suite selected all ten
cached node/test compiler profiles during Make setup. Their recipes compile
small fixtures directly and consume none of those object epochs. The new
regression fails on the saved entry Makefile with all ten unwanted profiles.

Reuse the existing exact standalone-target allowlist to select no object
profiles when every requested goal is in that list. Default, unknown and
mixed node/benchmark invocations retain their existing selection. Source
capture, compiler/profile key algorithms, node publication rules and all
node/test compile flags are unchanged. The standalone recipes still compile
their fixtures normally.

## Measurements

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, Bash 5.2.21, ordinary warm
filesystem caches and ambient host load. No live node, datadir or network
fixture was used. The standalone suite dry run was measured sequentially
three times before and after; timings are informational, never assertions.

| Setup observation | Entry Makefile | Changed Makefile |
|---|---:|---:|
| Selected cached object profiles | 10 | 0 |
| Wall time, run 1 | 11.72 s | 5.95 s |
| Wall time, run 2 | 7.73 s | 5.99 s |
| Wall time, run 3 | 7.73 s | 5.97 s |
| Median wall time | 7.73 s | 5.97 s |

The median improvement is 1.76 seconds (about 23%) in benchmark setup,
not end-to-end IBD or time-to-tip. Both versions retained source capture and
generated-view freshness checks. A preceding baseline dry run took 7.72 s.
The higher first repeated baseline is reported, not discarded.

Reproduce by saving the entry working-tree Makefile, then running
`make -f <saved-Makefile> -n bench-fresh-sync-selftest` and
`make -n bench-fresh-sync-selftest` under `/usr/bin/time`. The measured runs
also loaded a second Makefile containing only
`$(info benchmark setup profiles: $(ZCL_EPOCH_PROFILES))` to observe the
actual selector without changing requested goals. Do not substitute a source
identity or compiler fingerprint. Tracing with strace was unavailable because
ptrace is restricted; no timing or event claim relies on it.

## Validation

- `bash tools/scripts/bench_sync_bootstrap_selftest.sh`: 31 bootstrap cases
  and 34 profile-selection cases pass. The saved entry Makefile fails the
  first standalone profile assertion. A temporary mutant that also skipped
  profiles for mixed goals fails on `bench_fresh_sync z23`.
- `make bench-fresh-sync-selftest`: the full current fixture suite passes.
- `make bench_fresh_sync`: succeeds in 7.58 s, including the bootstrap,
  profile, output, height-demand and integer-observation guards.
- Shell syntax, discarded-status, pipefail-status, shell-host-assumption
  and architecture-tree gates pass. Tracked-tree shell gates do not include
  the previously untracked bootstrap script; its syntax and executable
  regression were checked directly.
- `make lint-fast` reached a 50-second timeout during setup without a gate
  verdict. Aggregate lint remains incomplete, not passed.
- `git diff --check` and `git diff --cached --check` pass. The exact
  incremental Makefile and script diffs were reviewed. Excluding this new
  note, the staged diff and all other tracked unstaged diffs compare
  byte-for-byte with entry copies.

No C source, consensus predicate, validation threshold, optional acceleration
policy, peer scheduler, database or node runtime changed in this slice.
No secrets, logs, caches, binaries, generated files or temporary benchmark
output belong to it. Integration depends on the earlier pending standalone
allowlist; do not accidentally fold unrelated working-tree edits into it.

Publication is incomplete: fetch cannot write `.git/FETCH_HEAD` because that
filesystem is read-only, `origin/main` is unavailable locally, and the origin
host cannot be resolved. Staging the first draft of this new note succeeded;
a subsequent attempt to unstage only this note failed because
`.git/index.lock` could not be created on the read-only filesystem. Its latest
corrections therefore remain unstaged. Earlier staged work is unchanged.
No commit, push, upstream integration or remote-SHA verification is claimed.
Remaining setup time and real observer cost under isolated IBD load are
follow-up measurements; this note makes no chain-sync speed claim.
