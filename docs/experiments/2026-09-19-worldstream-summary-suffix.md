<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: snapshot-summary lookup after an unrelated suffix

This slice reduces display-only observation work in `tools/bench_fresh_sync.c`.
It changes no node, peer scheduling, database, validation, or consensus code.
Optional acceleration and independent ZClassic validation remain unchanged.
These measurements establish observer cost, not end-to-end IBD improvement.

## Baseline and reproduction

Branch: `agent/worldstream-ibd-20260918`.
HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`.
The starting checkout already contained extensive staged and unstaged work;
this slice is relative to those working bytes, not pristine HEAD.
Starting `tools/bench_fresh_sync.c` SHA-256:
`d6f557e349432293a60081e5a0557bba1fa9c69999f9167120b1212d44f7b744`.
Resulting source SHA-256:
`36fa8fdd6b3364aea846ce09eaa5c1b9b1684227027c992c34a4d3bb9fd2ae87`.

Host: Linux x86_64, AMD EPYC 7402P, GCC 14.2.0, C23, `-O2`.
Fixtures use warm local temporary files and ambient host load. No node,
network, production datadir, or credentials are involved.

The reverse log scan previously tested only the last `U` candidate before
falling back to enumerating all summary matches in a chunk. A trailing
unrelated `U` therefore defeated the fast path even when a valid summary
was immediately before it.

For 2,000 lookups of a 16 KiB chunk containing 1,024 summaries followed by
an unrelated `U`:

| Observation | Before | After |
|---|---:|---:|
| Substring searches | 2,050,000 | 0 |
| Wall time, three trials | 52.366 / 48.840 / 45.896 ms | 6.335 / 6.300 / 6.291 ms |

The new chunk helper walks at most 64 candidate bytes backward from the last
`U`, returning the latest complete marker. Longer suffixes retain the existing
bulk substring fallback. The 16 MiB log budget, chunk overlap, binary-log
refusal, summary line limits and phase observation behavior are unchanged.
Separating chunk lookup also keeps the modified functions below the existing
complexity cap, without raising any threshold.

## Regression and validation

```sh
bash tools/scripts/bench_fresh_sync_summary_suffix_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_summary_suffix_selftest.sh --baseline /tmp/worldstream-phase-batch/before.c
make bench-fresh-sync-selftest bench_fresh_sync
```

The optional final source argument permits comparison with saved baseline
bytes. Without `--baseline`, the old source fails the bounded-work assertion.
Tests check exact latest offsets, false candidates at distances 8, 9, 62, 63,
64, 65, 128 and 15,000, and dense false-candidate fallback. Timing is reported
but is not a flaky pass/fail threshold. The test is wired into the existing
benchmark suite. Six existing summary fixtures only widen their source
extraction start to include the helper; their assertions are unchanged.

The focused regression, GCC analyzer, strict C23 syntax/warning checks, shell
syntax, complete benchmark suite/build and whitespace checks pass. Existing
suite coverage includes chunk overlap, the scan budget, binary input, oversized
lines, polling cadence, RPC outcomes and measurement deadlines.
The architecture check passes through its direct gate script.

`make lint-fast` and the Make architecture target were interrupted after
their prerequisite stage stalled. Running all 32 fast gates through the
existing lint runner completed with four failing gates: root `.agents`/`.codex`
entries, benchmark complexity, stale flag-reference lines, and denied Windows
scratch-directory access. After the chunk-helper refactor, the complexity
gate reports only the pre-existing `phase_log_poll`, `wait_for_cookie`, and
`main` violations; neither changed function violates its cap. No lint baseline
or acceptance assertion was weakened. Full publication evidence remains red.

## Publication boundary

No commit or push was possible: `.git` is read-only (`git fetch origin main`
failed opening `.git/FETCH_HEAD`), and the read-only remote branch query failed
because GitHub DNS was unavailable. The branch is unchanged. No remote SHA
equality is claimed, and no unrelated staged work was committed.
Temporary baseline bytes, logs and a review patch remain under
`/tmp/worldstream-phase-batch`; none belongs in a commit.
