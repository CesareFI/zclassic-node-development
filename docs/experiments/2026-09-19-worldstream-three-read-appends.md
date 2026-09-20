<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: avoid read amplification through the third phase-log read

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The cold-sync benchmark switched from unbuffered to buffered observation as
soon as a log append exceeded 8,192 bytes. Seeking a freshly opened buffered
stream to an unaligned cursor reread earlier log bytes. For 1,000 appends of
8,193 bytes, the observer read 37,365,626 bytes for 8,193,000 new bytes.

The scanner already reads two 4 KiB early-stop chunks followed by 64 KiB chunks.
Keep observation unbuffered through that third read (73,728 appended bytes).
Larger backlogs retain buffering. Identity/truncation checks, cursors, marker
overlap, early stopping, phase timestamps and the 16 MiB poll budget are
unchanged. This changes benchmark observation only, not node behavior.

The baseline is the working source at entry, SHA-256
`d98a48cb77d06556a18c5d949295d49bb57046afd6c71bf05b62f656ed3efa94`,
not pristine HEAD. The slice changes only the buffering threshold/comment,
the existing small-append regression and this report. Prior staged, unstaged
and untracked work is preserved. Temporary evidence and an isolated patch are
under `/tmp/worldstream-three-read/`.

## Measurement

Linux x86_64, GCC 14.2.0, C23 `-O2`; synthetic local log, warm page cache,
uncontrolled ambient host load. Three sequential baseline/candidate trials,
1,000 append-and-observe polls per size. Each size starts from an unaligned
73,729-byte extent. No node, network or production datadir participates.

| Bytes appended per poll | Baseline bytes read | Candidate bytes read | Baseline median seconds | Candidate median seconds |
|---|---:|---:|---:|---:|
| 8,193 | 37,365,626 | 8,193,126 | .022416 | .021020 |
| 16,384 | 49,153,126 | 16,384,126 | .029683 | .027671 |
| 65,536 | 73,729,127 | 65,536,126 | .080147 | .078268 |
| 73,728 | 102,401,130 | 73,728,130 | .091604 | .087833 |

Read accounting includes a small `/proc/self/io` observation. It measures
userspace bytes returned by reads, not physical disk traffic. The 8,193-byte
case reduces reads by about 78% and median observer wall time by about 6%.
The tradeoff is one extra read syscall per poll for the intermediate sizes;
the candidate is bounded to three payload reads through 73,728 bytes. Larger
appends retain the existing behavior. These are observer microbenchmarks,
not end-to-end IBD or time-to-tip results.

## Validation and limits

The extended regression fails the baseline at 8,193 bytes. The candidate passes
exact read budgets and syscall ceilings across 13 sizes, including both sides
of the threshold, cursor advancement and every marker split across polls:

```sh
bash tools/scripts/bench_fresh_sync_small_append_selftest.sh --analyze
make bench-fresh-sync-selftest
```

Both pass. The focused fixture compiles with C23 `-Wall -Wextra -Werror
-pedantic` and GCC `-fanalyzer`. The aggregate exercises log rotation,
truncation, chunk boundaries, early stopping, deadlines and benchmark outcomes.
Shell syntax, architecture-tree, shell-host-assumption, pipefail-status and
discarded-status checks pass. `git diff --check` passes.
`make lint-fast` exceeded a 50-second bound during initialization; no aggregate
lint pass is claimed.

The complete benchmark links with its existing Makefile compiler flags. A
whole-file strict object compile refuses the same seven diagnostics in both
baseline and candidate: five ignored `system` results and two potentially
truncated copy commands. No warning suppression or unrelated repair was added.
The public node binary is unavailable; no live-chain acceptance is claimed.

Consensus, cryptographic validation, optional acceleration policy and
Hetzner-owned scheduling/database/runtime surfaces are untouched. The exact
slice diff contains no secrets, logs, binaries, caches or generated artifacts.

Publication is incomplete: `.git` is read-only, fetch cannot write
`FETCH_HEAD`, and remote branch lookup cannot resolve GitHub. No commit, push
or exact remote-SHA verification is claimed. Do not stage either complete dirty
source file as this slice; each contains substantial earlier work.
