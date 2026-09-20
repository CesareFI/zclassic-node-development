<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fresh-sync benchmark integration

Entry branch: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with substantial pre-existing
uncommitted Worldstream changes. This slice unblocks the complexity gate for
that benchmark work; it does not claim a measured IBD speedup.

The entry source's `main()` measured M=63 against a shrink-only M=55 pin.
The repository complexity gate failed on exactly this function. Extracting
startup waiting and cookie loading into `wait_for_cookie` restores M=55;
the helper is below the default cap of 15. No baseline allowance changes.
The polling interval, 600-poll bound, progress diagnostics, child handling,
credential buffer size and phase measurement logic retain their behavior.

The new `bench_fresh_sync_startup_selftest.sh` compiles the actual startup
routine against a fake clock and child, with inert fixture cookie bytes.
Eight cases cover immediate/delayed readiness, timeout, child exit, readiness
at the last poll, wait failure, a cookie without newline, and cookie-open
failure. The last case preserves the existing behavior of proceeding with an
empty cookie; this extraction does not harden credential loading. The saved
entry block and extracted routine produce byte-identical fixture output.
Shortening the startup bound to 599 iterations fails the regression.
There are no actual sleeps, network calls, nodes or production datadirs.

Reproduce with:

```bash
bash tools/scripts/bench_fresh_sync_startup_selftest.sh --analyze
make bench-fresh-sync-selftest
build/bin/z23-lint check-cyclomatic-complexity
```

An optional final source path exercises the saved inline baseline as well.
The new fixture is wired into the existing benchmark target; the HTTP fixture
extractor now stops before the new startup helper. Other dirty work is outside
this slice. Entry source SHA-256 and final source SHA-256 are recorded below.

| Source | SHA-256 |
|---|---|
| Entry working file | `c23b6b649d0f5b58a2508295417cc22cc3f0d5e7ecac5e62b4eaaedbac7053ee` |
| Extracted startup | `6fad57cf209373f7a600b8de7ac5caa93bb48def8e3af4df06acd786c89e7608` |

Validation on Linux x86_64, GCC 14.2:

- All six benchmark scripts pass directly: log scanner, startup, command
  observations, HTTP deadlines, phase timestamps and completion outcomes.
- Startup, timing and outcome fixtures pass C23 `-Wall -Wextra -Werror` and
  GCC `-fanalyzer`. The log fixture retains its exact 16 MiB / 4,096-read budget
  for twenty polls; entry observation took 0.016177 seconds (informational).
- The complexity gate and its selftest, architecture, core root mirror,
  no-API-keys, no-Python, discarded-status, pipefail-status-pipe and
  shell-host-assumptions checks pass.
- The core seal verifies 554 files and 80 sections. No node runtime,
  consensus, validation, acceleration policy, scheduling or database code
  changes. The owned diff contains no secrets or generated artifacts.
- Shell syntax and `git diff --check` pass.

Whole-source strict compilation reports the same seven pre-existing errors
before and after extraction: five ignored `system()` results and two possible
copy-command truncations. These are not waived. Direct compilation and linking
with the existing benchmark recipe's flags succeeds, retaining those warnings;
the resulting temporary binary was not run. `make lint-fast` times out
at 50 seconds during prerequisites. The make benchmark/combined-check runs
were interrupted after stalling during prerequisite work; the latter also
reports read-only Git configuration while preparing Tor. Direct fixture and
lint execution supplies the focused evidence above, not full integration
acceptance. The public node binary is unavailable for navigation in this tree.

Publication remains incomplete. Fetch cannot write `.git/FETCH_HEAD`, and
origin lookup fails on GitHub DNS. No commit, push or exact remote-SHA equality
is claimed. Branch identity is preserved. Git accepted staging the new startup
fixture, but restoring that path's index state failed on read-only
`.git/index.lock`; no pre-existing staged file was changed by this slice.
