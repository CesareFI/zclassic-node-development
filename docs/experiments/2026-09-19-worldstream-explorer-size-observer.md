<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream explorer-size observation cost

Branch: `agent/worldstream-ibd-20260918`; base commit:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The checkout already contained
substantial staged and unstaged Worldstream work. This slice preserves it and
measures the working-tree implementation saved before this slice, not a clean
checkout of that commit. Host: Linux x86_64, GCC 14.2.0, Bash 5.2.21.

The fresh-sync benchmark checks four explorer page sizes after reporting its
sync milestones. Each check previously piped the entire response through an
additional Bash process and `wc`. Curl now downloads the same full response
to `/dev/null` and reports `%{size_download}` directly. The existing command
reader rejects counters from failed transfers; the two-second HTTP deadline
is unchanged. This reduces diagnostic overhead after the milestones. It does
not change the measured time-to-tip or establish faster IBD.

Three warm-cache fixture runs of 100 observations of a one-MiB binary body:

| Measurement | Before | After |
|---|---:|---:|
| Wall time, run 1 | 0.843131 s | 0.227626 s |
| Wall time, run 2 | 0.838868 s | 0.220708 s |
| Wall time, run 3 | 0.828583 s | 0.210661 s |
| Median | 0.838868 s | 0.220708 s |
| Extra Bash/wc invocations per check | 2 | 0 |

The median fixture observer cost fell about 74%. The stand-in models curl's
output and status contract, not network transfer cost. A separate installed
curl check verifies byte counting on a one-MiB NUL-filled local file and
failure status on a missing file. No node, network listener, real credentials
or production datadir is involved. Timing is descriptive; only behavior and
process counts are regression gates.

Reproduce after saving the pre-change C source to a temporary file:

```bash
bash tools/scripts/bench_fresh_sync_page_size_selftest.sh --bench /tmp/bench-before.c
bash tools/scripts/bench_fresh_sync_page_size_selftest.sh --bench --analyze
```

The first command passes byte-count and failure checks but intentionally fails
the redundant-process budget. The test compiles the production functions and
covers all four paths, binary bytes, empty bodies and partial failed transfers.
The existing deadline stand-in now understands curl's output-discard and
byte-counter arguments. The new regression is registered in the existing
`bench-fresh-sync-selftest` Make target. GCC analysis is opt-in so it is not
imposed on other compilers.

Validation:

- New regression, installed curl contract, extracted production C23 code with
  `-Wall -Wextra -Werror` and GCC `-fanalyzer`: pass.
- Existing command-output and HTTP-deadline regressions with `--analyze`:
  pass, including silent/partial responses and two-second timeouts.
- Existing phase-log, completed-log, startup, outcome/grace and height-demand
  regressions invoked directly: pass.
- Existing timing regression: fails on both saved pre-change and changed
  source with the identical assertion (completion 19 s, expected 21 s).
  This slice does not change that assertion or the timing loop.
- Benchmark executable builds with the existing target's compiler flags.
  Adding strict warnings to the full file fails on pre-existing unchecked
  `system` calls and copy-command truncation warnings; the saved pre-change
  source reproduces those warnings. No warning suppression was added.
- `make bench-fresh-sync-selftest` and `make lint-fast`: each reached the
  imposed 45-second limit during setup, before reporting results. No complete
  Make-suite or lint pass is claimed.
- Direct pipefail-status, discarded-status, shell-host-assumption and
  architecture-tree checks: pass. These tracked-tree checks do not establish
  coverage of the new untracked script; its Bash syntax and focused execution
  pass separately. ShellCheck is unavailable. `git diff --check`: pass.

Only benchmark observation, regression fixtures and test wiring changed.
Consensus, independent validation, optional acceleration, peer/request
scheduling, database tuning and node runtime are unchanged. The exact slice
diff was reviewed; no secrets, binaries, logs, caches or temporary outputs
belong to it. Temporary baselines and outputs live under `/tmp`.

Publication remains blocked: `.git` is read-only, so fetching cannot update
`FETCH_HEAD`; an independent `git ls-remote origin` also fails to resolve the
origin host. There is no new commit, push or verified remote SHA. The branch
and HEAD remain as recorded above. Before publication, preserve and separate
the earlier dirty work, resolve the existing broader test/lint limitations,
and rerun the required gates with writable Git metadata and working origin
access.
