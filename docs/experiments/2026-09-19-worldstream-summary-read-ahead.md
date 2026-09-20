<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: avoid reverse-summary read amplification

The fresh-sync benchmark scans backward for its snapshot summary in explicit
16 KiB chunks. Buffered stdio can also read preceding partial blocks during
seeks, so an unaligned log extent causes redundant reads. Disable buffering
only on this short-lived summary stream; retain the existing search budget,
marker overlap, exact line extraction and failure handling. A buffering
refusal logs context and retains the existing stream behavior.

Baseline: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with extensive pre-existing work.
The pre-slice `tools/bench_fresh_sync.c` SHA-256 is
`ac5b57a93b587298cdaa64eb606457ee2ea4f5925d339d9be015c2571fffc687`.
This slice adds four C lines, registers one regression and adds this record.
It does not incorporate the other working changes.

Measured on Linux x86_64, GCC 14.2.0, warm filesystem cache, synthetic text
logs with a summary at the beginning. Each trial performs 20 complete summary
lookups; timings below are medians of three trials. Kernel `rchar` includes
stdio read-ahead and a small accounting-read overhead.

| Log bytes | Before read bytes | After read bytes | Before median ms | After median ms |
|---:|---:|---:|---:|---:|
| 4,194,304 | 83,968,114 | 83,896,434 | 17.798 | 18.507 |
| 4,194,305 | 83,973,243 | 83,896,443 | 22.600 | 19.306 |
| 4,198,399 | 104,934,525 | 83,978,345 | 22.944 | 18.949 |

The most amplified case reads about 20% fewer bytes and takes about 17% less
time. The aligned case showed a small timing increase; timing is informational,
not an acceptance threshold. These are benchmark-observer costs, not measured
end-to-end IBD or time-to-tip improvements. No live node or datadir was used.

Reproduce:

```bash
bash tools/scripts/bench_fresh_sync_summary_io_selftest.sh --analyze
make bench-fresh-sync-selftest
```

The focused script accepts an optional source filename and `--baseline` to
report without enforcing its read-byte budget. The pre-slice source fails
the normal regression. The regression checks exact summary text at aligned,
one-byte-offset and near-page-boundary extents. Kernel read-byte checks are
explicitly unobserved on hosts without `/proc/self/io`; content checks still
run there. All files are isolated temporary fixtures and are removed on exit.

Validation passed: the full `make bench-fresh-sync-selftest` target, focused
C23 `-Wall -Wextra -Werror -pedantic` compilation and GCC `-fanalyzer`, Bash
syntax, pipefail-status, discarded-status, shell-host-assumptions and
architecture-tree checks, and both staged and unstaged `git diff --check`.
The complete benchmark also builds with its ordinary flags. Strict compilation
of that complete tool fails on existing GNU ternary, discarded `system()`
results and truncation warnings; the pre-slice source reproduces them.
`make lint-fast` exceeded a 60-second bound during preparation, so completion
of the aggregate lint target is not claimed. The targeted checks above were
run directly and passed.

Consensus, cryptographic validation, optional acceleration and Hetzner-owned
scheduling/database/runtime behavior are unchanged. The slice includes no
credentials, production data, logs, binaries, caches or generated build output.

Publication is blocked by the environment: `.git` is read-only, preventing
fetch/commit, and origin cannot resolve `github.com`. No commit, push or remote
SHA verification is claimed. The isolated patch and raw measurements remain
under `/tmp/worldstream-summary-io/` for review and later publication.
