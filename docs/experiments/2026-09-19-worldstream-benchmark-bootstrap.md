<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream standalone benchmark bootstrap

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. This slice uses the existing
dirty working tree, including its pending fresh-sync benchmark regressions.
Earlier staged and unstaged changes are preserved. Linux x86_64, GCC 14.2.0,
missing vendor/Tor archives, no live node or chain fixture.

## Problem and change

`make -n bench-fresh-sync-selftest` attempted to remake the included
`build/identity/vendor-inputs-ready.mk`, invoking `vendor-ready` before any
benchmark recipe. Make debug output identifies that invocation. The baseline
reached a 20-second diagnostic timeout (exit 124); no completion time is known.
Earlier experiment notes reported 50/60-second setup timeouts for this suite.

The standalone driver links only its own source and platform clock/log helpers;
its regression scripts compile isolated fixtures. Vendor libraries and Tor
are unnecessary for those targets. An exact list now exempts the driver,
its direct binary target and its named selftests from vendor/Tor bootstrap.
`bench-sync`, which also builds the node, is deliberately absent. Default,
unknown and mixed node goals retain bootstrap. Source capture, compiler
identity, profile selection, validation and artifact verification are unchanged.

The regression evaluates the actual Makefile bootstrap conditionals in a
temporary fixture. Only vendor/Tor build recipes are replaced with marker
writes. Its baseline failure observes both bootstrap markers for the standalone
driver; the fix passes 31 cases, including reversed mixed-goal order, explicit
vendor repair, unknown goals, the default build and `bench-sync`.

## Measurements and validation

| Invocation | Result | Wall time |
|---|---|---:|
| Baseline benchmark-suite dry run | Timeout in vendor setup | 20.00 s bound |
| Changed benchmark-suite dry run | Exit 0 | 7.65 s |
| Changed benchmark suite | All 18 existing scripts and new bootstrap guard pass | 26.35 s |
| Changed `make bench_fresh_sync` | Build and bootstrap/height guards pass | 8.72 s |

These are single local observations, not statistical distributions or live
IBD/time-to-tip evidence. The compiler emits seven existing driver warnings;
this slice changes no C source or compiler flags and suppresses no warning.

Reproduce the focused guard with:

```bash
bash tools/scripts/bench_sync_bootstrap_selftest.sh /tmp/Makefile.before
bash tools/scripts/bench_sync_bootstrap_selftest.sh
make bench-fresh-sync-selftest
make bench_fresh_sync
```

The first command requires a saved pre-change working-tree Makefile and is
expected to fail. Timings are descriptive; the regression grades bootstrap
events, never elapsed time.

- Height-demand and nine timing scenarios also pass C23 strict compilation
  and GCC `-fanalyzer` through their existing `--analyze` modes.
- Bash syntax, direct architecture-tree, pipefail-status, discarded-status
  and shell-host-assumption gates pass. Tracked-tree shell scans do not cover
  the new untracked script; its syntax and executable fixture are checked
  separately.
- `make lint-fast` reaches a 45-second timeout before a lint verdict. Its
  vendor prerequisites remain required; no aggregate lint pass is claimed.
- `git diff --check` passes. Exact incremental Makefile changes and the new
  test were reviewed. All other tracked staged/unstaged diffs compare
  byte-identically with entry snapshots. No core source has a diff.

Only the Makefile bootstrap selection/test wiring, new regression and this
note belong to this slice. No consensus behavior, optional-acceleration policy,
peer scheduling, database tuning, production state or node runtime changed.
No secrets, generated files, logs, caches, binaries or benchmark output belong
to the proposed change.

Publication remains incomplete: fetch cannot write `.git/FETCH_HEAD` because
Git metadata is read-only, and `git ls-remote origin` cannot resolve the
origin host. `origin/main` is unavailable locally. No commit, push, upstream
integration or exact remote-SHA verification is claimed. Integration must
isolate this small Makefile delta from earlier pending work and complete lint
before publication.
