<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream benchmark RPC HTTP error observations

Branch: `agent/worldstream-ibd-20260918`, HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The baseline is the working
`tools/bench_fresh_sync.c` at session entry, including earlier pending work.

The benchmark's curl RPC reader accepted HTTP error bodies because curl
normally exits successfully after receiving them. A body containing an
`at_tip` state could establish a false timed milestone and trigger an
unnecessary height RPC. This undermines time-to-tip comparisons and adds
observer work during endpoint failure. Explorer observers already reject
HTTP errors; the RPC reader now uses the same `--fail` option.

The regression extracts the actual command reader, RPC helper, field readers
and state-transition code. A local curl stand-in supplies HTTP statuses and
counts requests. No node, network, datadir or real credentials participate.
Results are deterministic operation counts on Linux x86_64 with GCC 14.2.0,
not measured live IBD speedups. The clock is a fixture.

| Observation | Entry baseline | Fixed |
|---|---:|---:|
| False tip samples across HTTP 400, 401, 403, 404, 429, 500, 503 | 7/7 | 0/7 |
| Unnecessary height requests after those errors | 7/7 | 0/7 |
| Requests per failed transition sample | 2 | 1 |
| Successful HTTP 200 transition requests | 2 | 2 |

Repeated failed samples remain unavailable. A later successful response still
establishes the transition and height. The regression fails on the baseline at
the first HTTP error. It is wired into `bench-fresh-sync-http-error-selftest`,
already required by the benchmark build and aggregate selftest.

Reproduce the focused checks without building or running a node:

```bash
bash tools/scripts/bench_fresh_sync_rpc_http_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_http_error_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_unavailable_rpc_selftest.sh
```

The new script also accepts `--baseline` followed by an old source path.
All 50 `tools/scripts/bench_fresh_sync_*selftest.sh` scripts pass, including
command failure/truncation, deadline, proxy, curl configuration, phase-log,
startup, cleanup, timing and outcome coverage. The new fixture compiles with
C23, `-Wall -Wextra -Werror -pedantic`, and passes GCC `-fanalyzer`.
Bash syntax, discarded-status, pipefail-status, shell-host assumptions, and
staged/unstaged `git diff --check` pass. The new test was separately parsed
and executed, then included in the tracked-tree shell checks after staging.

The complete benchmark links using its Makefile recipe flags. Strict full-file
compilation/analysis remains blocked by existing unchecked `system()` results
and potentially truncated certificate-copy commands, also reproduced against
the entry baseline. Those unrelated warnings were not suppressed or changed.
`make lint-fast` timed out after 60 seconds before a verdict. The Make selftest
invocation was interrupted during initialization; its two scripts pass when
run directly. The public-node build cannot initialize the missing Tor
submodule because Git metadata is read-only; it was interrupted. Full lint,
public-node build, integration acceptance and live time-to-tip are unverified.

Owned changes are one RPC curl option and its comment, one Makefile test
invocation, the regression and this note. Consensus, independent validation,
optional acceleration, peer/request scheduling, databases and runtime code
are unchanged; `git diff HEAD -- core` is empty. Prior staged and working edits
remain in place. The new regression alone was added to the index: `git add`
succeeded, but both scoped restore/reset attempts were refused because
`.git/index.lock` is read-only. No secrets, production data,
generated artifacts, logs, caches or binaries belong to this slice.

Entry benchmark source SHA-256:
`269c7c128eaeb81e76fba399f43d0b39b6255c7b70bb2487a86180d8f3b87f2c`.
Fixed benchmark source SHA-256:
`4f29f6d7065067626d7dfc8039143617f129c25c9b5ed3dfa3d79e2ea357d321`.

Publication is blocked: fetching cannot write `.git/FETCH_HEAD`, `origin/main`
is absent locally, and origin lookup cannot resolve GitHub. No commit, push or
remote SHA verification is claimed. Restore permitted Git writes and origin
access, separate this slice from prior dirty work, integrate upstream, and run
required publication gates before pushing only this development branch.
