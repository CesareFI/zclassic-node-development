<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound phase-log normalization windows

This slice changes only `phase_log_normalize` in the standalone fresh-sync
benchmark and extends its existing `bench_fresh_sync_nul_scan_selftest.sh`.
The existing Makefile aggregate already runs that fixture. No consensus,
validation, optional acceleration, peer scheduling, database or runtime
behavior changes.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with substantial pre-existing
staged, unstaged and untracked work. Comparison uses the working C file
captured at entry, SHA-256
`36fa8fdd6b3364aea846ce09eaa5c1b9b1684227027c992c34a4d3bb9fd2ae87`.
The candidate C file is
`94609f09b4f2f1134ce4b37ed06aeb01b024152b5762d0297fedff2edf991e9b`.
These are file identities, not clean commit identities or publication evidence.

## Witness and change

Two NULs exactly 64 bytes apart caused the previous normalization heuristic
to treat the entire remaining chunk as dense binary input. A text suffix
therefore received a scalar byte walk. The observer now normalizes at most
64 bytes before looking for the next NUL. A NUL immediately after the window
continues directly, avoiding an extra search call on dense input.

NULs still become newlines, so they neither conceal later milestones nor
concatenate marker fragments. The regression adds the paired-NUL benchmark
and 20,769 byte-for-byte oracle cases covering empty/short inputs, window
boundaries, high-bit bytes and untouched guards. Timing is reported, not used
as a flaky pass threshold. The existing binary scanner regression also covers
all byte values, all first-chunk NUL offsets and split-marker non-concatenation.

## Measurement

Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, C23 at `-O2`, warm filesystem
cache, ambient host load. Each sample scans a temporary 16 MiB log twenty
times. One real milestone at the end and four absent milestones require the
complete scan. Fixture creation and compilation are outside the timer.
Medians of three alternating baseline/candidate runs:

| Padding | Baseline seconds | Candidate seconds |
|---|---:|---:|
| Text only | 0.127931 | 0.126744 |
| One NUL per 4096 bytes | 0.132139 | 0.131190 |
| All NUL | 0.229275 | 0.235631 |
| NULs at offsets 0 and 64 per 4096 bytes | 0.331863 | 0.136842 |

The paired case is about 59% faster, with an approximately 3% dense-input
cost. This is synthetic observer evidence only. Real-log input prevalence
and end-to-end time-to-tip improvement remain unmeasured.

Reproduce using the current source, or supply a captured baseline C path:

```sh
bash tools/scripts/bench_fresh_sync_nul_scan_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_binary_log_selftest.sh --analyze
make bench-fresh-sync-selftest
make bench_fresh_sync
```

## Validation and publication

The aggregate selftest and standalone benchmark build passed. Focused
fixtures passed GCC warnings-as-errors and static analysis; the extended
fixture also passed Clang 20. Both NUL fixtures passed AddressSanitizer and
UndefinedBehaviorSanitizer with leak detection disabled; no leak-check claim
is made. Shell syntax, architecture, shell-host assumptions and staged and
unstaged `git diff --check` passed.

The standalone build still warns about existing unchecked `system()` calls
and copy-command path truncation, outside this slice. Full `make lint` did
not reach gate results within a 60-second bound. A direct complexity check
reports existing violations in `phase_log_poll`, `wait_for_cookie` and `main`;
their same complexity values reproduce on the captured baseline. The changed
normalizer remains below the cap. No threshold or baseline was relaxed.

Exact slice review found only the normalizer, fixture extension and this
report. Existing work is preserved; no secrets, logs, binaries, caches,
datadirs or temporary benchmark output belong in the slice.

Publication is blocked: `.git` is read-only and origin lookup fails because
`github.com` cannot resolve. No commit or push was made, upstream integration
could not be checked, and remote SHA equality is unverified. The required
development branch remains checked out. A subsequent permitted run must
isolate this delta from the accumulated work, complete the integration gates,
commit and push only the development branch, then verify the remote SHA.
