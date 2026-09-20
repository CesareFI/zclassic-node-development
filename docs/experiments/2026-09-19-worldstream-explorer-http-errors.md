<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reject HTTP error pages in fresh-sync measurements

Scope: `tools/bench_fresh_sync.c` explorer readiness and page-size observation.
Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The starting checkout already
contained substantial uncommitted Worldstream changes. This slice adds only
HTTP-error refusal, its focused test and Makefile registration, and this note.

The observers required curl exit success but did not request HTTP-error
failure. An error response containing `Latest Blocks` could establish explorer
readiness and its body length could be reported as an explorer page size.
That corrupts the benchmark's time-to-readiness observation during startup or
IBD. Both explorer requests now use `--fail`; existing transfer-status checks
reject the response and size counter. Successful responses retain their
existing marker and complete-transfer requirements.

On Linux x86_64 with GCC 14.2 and C23 `-O2 -Wall -Wextra -Werror`, the fixture
observed:

| Response | Before: ready / size | After: ready / size |
|---|---|---|
| HTTP 200, `Latest Blocks` | true / 13 | true / 13 |
| HTTP 404, same body | true / 13 | false / 0 |
| HTTP 429, same body | true / 13 | false / 0 |
| HTTP 500, same body | true / 13 | false / 0 |
| HTTP 503, same body | true / 13 | false / 0 |

The test compiles the actual observers and supplies a curl stand-in modelling
HTTP failure status 22 and body suppression. A real HTTP fixture could not bind
its local Unix socket in this environment. This is a deterministic observation
regression, not real-server qualification or an end-to-end IBD speed claim.
Installed curl separately passed the existing local-file observer tests.

Reproduce:

```bash
bash tools/scripts/bench_fresh_sync_http_error_selftest.sh --analyze
make bench-fresh-sync-selftest
```

The focused test accepts an optional source path; `--baseline` records the old
behavior. Removing `--fail` makes the regression fail at HTTP 404. The complete
fresh-sync selftest target passed. Existing curl-configuration, page-size and
readiness fixtures passed, including real curl against local files. Focused
GCC static analysis, shell syntax, architecture, pipefail/discarded-status
gates and `git diff --check` passed.

A stricter whole-file compile remains red on existing ignored `system()`
results and potentially truncated copy commands; the saved pre-slice source
reproduces those diagnostics. Full `make lint` was interrupted after its
prerequisite preparation stopped producing output; no full-lint pass is claimed.

Consensus and validation code are untouched (`git diff HEAD -- core` is empty).
This slice changes no node runtime, acceleration policy, peer scheduling,
database behavior or custody. Fixture outputs and compiler artifacts remain
under `/tmp`, outside the proposed source change.

Publication remains incomplete: fetching origin fails because `.git/FETCH_HEAD`
is read-only, and remote SHA lookup fails because GitHub DNS is unavailable.
An attempt to restore the index also encounters a read-only `.git/index.lock`.
No commit, push or exact remote-SHA verification is claimed.
