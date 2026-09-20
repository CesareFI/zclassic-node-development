<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream explorer readiness marker scan

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The baseline is the working-tree
benchmark before this slice, including earlier pending Worldstream work.
Linux x86_64, GCC 14.2.0, `-std=c23 -O2`; local temporary files, warm page
cache, uncontrolled ambient load. No node, peer, network or datadir is used.

The explorer readiness observer compared `Latest Blocks` at every possible
byte position until finding it. It now uses one bounded `memchr` per chunk
to skip a prefix with no possible first byte, then retains the scalar suffix
scan. Dense candidate bytes therefore retain the old scan rather than paying
for a separate search at every position. Overlap, binary response handling,
the HTTP deadline, full response draining and transfer-success requirement
are unchanged. The measurement concerns observer CPU/read overhead only;
it does not establish an end-to-end IBD or time-to-tip improvement.

Each sample below consists of five observations of the same 16 MiB file;
figures are medians of three samples in seconds. Timing builds disable the
comparison counter so instrumentation does not distort this comparison.

| Body | Before | After |
|---|---:|---:|
| No candidate bytes, no marker | 0.067877 | 0.025981 |
| All candidate bytes (`L`), no marker | 0.068354 | 0.066780 |
| One candidate byte per 8192 bytes, no marker | 0.068367 | 0.046212 |
| Marker at the end, otherwise no candidates | 0.068382 | 0.025930 |

The absent-marker fixture takes about 62% less time. The dense-candidate
fixture shows no material regression in these samples; this is descriptive
evidence, not a general throughput guarantee or a timing assertion.
Every version still consumes the complete 16 MiB on every observation.

The separate counted regression rejects the baseline: five absent-marker
observations perform 83,886,020 comparisons instead of zero. The changed
version performs zero; the late-marker case performs five. Coverage also
includes every marker split across reads, short/empty bodies, surrounding
and intervening NULs, complete draining after a match, nonzero transfer exits
and read errors. The script extracts and compiles the actual production
observer. No network subprocess is run in this fixture.

Reproduce with a saved pre-change source:

```bash
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh /tmp/before.c
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh --measure /tmp/before.c
bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh --measure
```

The first command is expected to fail the comparison budget. Source SHA-256:

- Before: `7f8352cbcceca1cccf8c168bfd296b3f981e621546a9a9323e3b9c93dba06b89`.
- After: `9f5f22fe5fea7affdc2b707e88e07df8af7b1f9eb1d297045b3cdd2f8ad98b4b`.

Validation:

- New regression, Bash syntax, C23 warnings-as-errors and GCC `-fanalyzer`
  pass. Existing readiness and outcome fixtures also pass with analysis.
- Direct execution of the 13 `bench_fresh_sync_*selftest.sh` scripts yields
  twelve passes and the existing timing failure: expected `t_done=21`, actual
  19. Baseline and changed timing failure logs are byte-identical; neither
  the timing test nor its assertions changed.
- Complete baseline and changed benchmark executables compile. Their seven
  existing warning messages are identical, with none suppressed.
- `make bench-fresh-sync-selftest` and `make lint-fast` each exceed a
  45-second bound during initialization, before aggregate results. No full
  suite or lint pass is claimed.
- Direct architecture-tree, pipefail-status, discarded-status and shell-host
  checks pass. These tracked-tree checks exclude the new untracked script;
  its syntax and compiled checks ran separately. `git diff --check` passes.

Owned changes are the five-line observer addition in `tools/bench_fresh_sync.c`,
one Make test invocation, the new regression and this note. The incremental
diff against saved working-tree files was inspected. Earlier pending work is
preserved. No consensus source changed. Optional acceleration policy, normal
independent validation, Hetzner-owned scheduling/database/runtime work and
production state remain untouched. No generated artifacts, temporary output,
logs, caches, binaries or secrets belong to this slice.

Publication is incomplete. `.git` is read-only, so fetch cannot write
`FETCH_HEAD`, and `origin/main` is absent. An independent query of the
authorized origin branch fails DNS resolution. No commit, push or remote SHA
verification is claimed. Cached remote-tracking equality is not remote
verification. Publication needs writable Git metadata, working origin access,
separation from earlier dirty work and completion of the outstanding aggregate
validation without weakening assertions.
