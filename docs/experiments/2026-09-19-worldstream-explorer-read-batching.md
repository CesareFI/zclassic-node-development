<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream explorer readiness read batching

Scope: `explorer_responding()` in `tools/bench_fresh_sync.c` and its existing
`tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh` regression. The
benchmark observer used 4 KiB body reads, including after finding the marker.
It now uses 64 KiB reads with the same marker overlap, complete-response drain,
read-error rejection and required successful curl exit. Stack use grows by
60 KiB in this standalone benchmark function; there is no allocation or node
runtime change. Consensus and independent validation are unchanged. Optional
acceleration remains optional. No Hetzner-owned component changed.

Branch: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Measurements use the existing dirty
working tree, not that clean commit. The production file was already modified
and the regression was already untracked. Their earlier changes are preserved;
the incremental diff is relative to their session-entry bytes.

## Baseline and result

Linux x86_64, GCC 14.2.0, C23 `-O2`, local warm 16 MiB temporary files,
three runs of five observations per shape. The extracted production reader
uses fixture open/close/error wrappers, not HTTP or a live node. Wall time is
descriptive; the gate asserts read-call count and behavior instead.

| Body shape | Before median, five polls | After median, five polls |
|---|---:|---:|
| No marker candidates | 26.047 ms | 12.349 ms |
| Dense false candidates | 63.354 ms | 48.376 ms |
| Sparse false candidates | 26.420 ms | 12.962 ms |
| Marker at end | 26.081 ms | 10.721 ms |
| Marker at beginning | 25.146 ms | 9.959 ms |

Each 16 MiB response needs 4,097 `fread` calls before and 257 after, including
the EOF call. These are library-call counts, not kernel syscall counts. The
new read-call assertion fails against the entry source. The timing reduction
is local-file observer cost only; it does not establish network, GUI or
end-to-end IBD improvement. Real HTTP delivery can have a different cost.

The regression retains its existing content shapes, adds the early-marker
drain case, and tests every marker split around both 4 KiB and 64 KiB
boundaries. Embedded NULs, incomplete markers, transfer failures and read
errors retain their existing acceptance behavior.

## Reproduction and validation

```bash
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh --measure
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh --analyze
make bench-fresh-sync-selftest
```

- Focused regression passes C23 `-Wall -Wextra -Werror -pedantic` compilation
  and GCC `-fanalyzer`. AddressSanitizer and UndefinedBehaviorSanitizer pass;
  LeakSanitizer cannot run under this environment's tracing, so that separate
  check is unavailable (`ASAN_OPTIONS=detect_leaks=0` for the successful run).
- The full Makefile benchmark selftest target passes, including its bootstrap
  prerequisite and all 36 listed script recipes. Additional HTTP configuration,
  proxy and height-demand regressions pass.
- The complete benchmark links with its existing Makefile recipe flags.
  Whole-file strict `-Werror` compilation/analysis fails on the same seven
  existing diagnostics before and after: five unchecked `system()` returns
  and two potentially truncated copy commands. The changed function's strict
  compile/analysis succeeds; no warning suppression was added to source.
- Direct discarded-status, pipefail-status and shell-host-assumption gates
  pass. Shell syntax and incremental whitespace checks pass. The regression
  remains untracked, so tracked-tree shell gates alone do not cover it.
- `make lint-fast` exceeds a 50-second bound during setup without a gate
  verdict (exit 124). This is an incomplete check, not a lint pass.
- The exact incremental diff was inspected. Existing staged bytes and all
  other tracked unstaged diffs remain identical to their entry snapshots.
  No secrets, production state, logs, binaries, caches or benchmark outputs
  are part of this slice. All runtime fixtures are temporary.

Production source SHA-256 before:
`94609f09b4f2f1134ce4b37ed06aeb01b024152b5762d0297fedff2edf991e9b`;
after: `353594969deac21751fe755209ad293e7cb11f09fd736f9e997be246578c4ead`.
Regression SHA-256 before:
`9f1485027ee7479cdfc7ee0ead55f8f3fcc546864f94efb959d59490d7ad9e03`;
after: `a0f7d91a1c12e9c9fd01fea66edf83eef1c2b4ade43ccbbcebb779727bd022e8`.

Publication is blocked: fetching cannot write `.git/FETCH_HEAD` because Git
metadata is read-only; `origin/main` is absent locally, and read-only
`git ls-remote origin` cannot resolve the origin host. No commit, push,
upstream integration or remote-SHA verification occurred. The branch remains
unchanged. Integrating this slice must preserve the extensive earlier work.
The next measurement should qualify real HTTP observer cost under isolated
IBD load; no live-chain time-to-tip result is claimed here.
