<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound summary searches to remaining candidates

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The cold-sync benchmark's display-only snapshot-summary lookup bisected possible
match positions, but each substring search still visited the entire suffix.
Repeated older summaries followed by a long unrelated suffix therefore scanned
already-excluded text at every bisection step. Temporarily terminate the writable
chunk after the last possible complete match, and restore the byte immediately
after the search. The latest match, 16 MiB file-read budget, and displayed
summary remain unchanged. No node validation or acceleration policy changes.

The baseline is the working source at entry, not pristine HEAD. Its SHA-256 is
`c08b065a44842edd725fc1cbfba5c53dcb70ce9b182ebbd2108a922555f6b2e4`.
Earlier staged, unstaged and untracked work is preserved. This slice changes
only the chunk reader, its existing fallback test's mutable-buffer signature,
one aggregate-test recipe line, and the new regression and this report.

## Measurement

Linux x86_64, GCC 14.2.0, C23 at `-O2`. Synthetic warm in-memory text contains
65 summaries spaced 16 bytes apart followed by unrelated text and a final `U`.
Baseline and candidate run sequentially, three repetitions each, with ordinary
ambient host load. These are observer microbenchmarks, not end-to-end IBD or
time-to-tip measurements. No node, network or production datadir participates.

| Input | Baseline | Candidate |
|---|---:|---:|
| 16 KiB: cumulative substring input bytes per lookup | 334,727 | 147,015 |
| 64 KiB: cumulative substring input bytes per lookup | 1,497,754 | 589,413 |
| 16 KiB: seconds for 20,000 lookups | .050175 / .041768 / .041520 | .010918 / .010888 / .010848 |
| 64 KiB: seconds for 20,000 lookups | .165716 / .165386 / .165581 | .023332 / .023488 / .023526 |

Median lookup time fell about 74% and 86%, respectively. The byte counter sums
string lengths handed to substring search; it does not claim actual CPU memory
traffic. Counting is disabled during timed repetitions. Sparse/absent/recent
match paths retain their existing behavior and work budgets.

## Validation and limits

`bash tools/scripts/bench_fresh_sync_summary_bounds_selftest.sh` passes with
C23 `-Wall -Wextra -Werror -pedantic` and GCC `-fanalyzer`. The entry baseline
fails its deterministic search-input budget. Dense fixture sweeps compare the
latest match with an independent linear oracle and check byte-for-byte buffer
restoration. Existing summary, fallback, suffix, window, chunk, overlap, I/O,
budget, latest-marker and binary-log regressions pass.

`make bench-fresh-sync-selftest` passes the full registered benchmark aggregate,
including its bootstrap and receipt-lock prerequisites. Shell syntax,
architecture-tree, shell-host-assumption, pipefail-status and discarded-status
checks pass. The exact slice diff was reviewed and `git diff --check` passes.

The complete benchmark links with its existing Makefile compiler flags. A
stricter whole-file `-Werror` build fails on seven pre-existing diagnostics:
five ignored `system` results and two potentially truncated copy commands.
Compiling the entry baseline reproduces all seven. Whole-file static analysis
also refuses the existing copy-command truncations. No warning suppression or
unrelated repair was added. `make lint-fast` exceeded a 50-second bound during
initialization; no aggregate lint pass is claimed. The public node binary is
unavailable, so live-chain acceptance was not run.

Consensus, custody, cryptography, optional acceleration policy and Hetzner-owned
scheduling/database/runtime surfaces are untouched. No secrets, logs, caches,
binaries or generated artifacts belong to this slice. Temporary baselines,
compiler output and the isolated patch reside in
`/tmp/worldstream-summary-bounds/`.

Publication remains incomplete: `.git` is read-only, fetching cannot write
`FETCH_HEAD`, and remote branch lookup fails to resolve GitHub. No commit,
push or exact remote-SHA verification is claimed. Do not stage the whole dirty
benchmark or Makefile as this slice; they contain extensive earlier work.
