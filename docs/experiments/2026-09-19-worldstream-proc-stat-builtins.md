<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream resource sampling without an external parser

Base commit: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The starting checkout already contained
staged, unstaged and untracked Worldstream work. This slice preserves it and
changes only the cold-start stopwatch's `parse_proc_stat_counters`, its
existing local regression, and four source-location annotations in
`engine/composition/flags.def`.

The resource sampler read CPU and RSS from an in-memory `/proc/PID/stat`
record by launching one awk process per sample. The parser now uses Bash
parameter expansion, array reading and integer arithmetic. It still locates
fields after the last closing parenthesis in the process name, keeps RSS as
exact decimal text, and reports unavailable CPU and RSS independently as -1.
CPU operands are checked before arithmetic; decimal leading zeros are
normalized and values or sums outside signed 64-bit range are unavailable.

Linux x86_64, Bash 5.2.21, warm tools/filesystem caches, three runs of 500
resource samples using the existing synthetic stat/io fixture and real caller:

| Measurement | Before | After |
|---|---:|---:|
| External parsers per resource sample | 1 | 0 |
| Wall seconds, run 1 | 5.675 | 3.648 |
| Wall seconds, run 2 | 5.629 | 3.763 |
| Wall seconds, run 3 | 5.587 | 3.623 |
| Median wall seconds | 5.629 | 3.648 |

Median resource-sampling cost fell by about 35%. The fixture replaces proc
file reads with shell functions; this measures parsing and caller overhead,
not kernel file access, node work or end-to-end IBD. No node, peer, production
datadir or network traffic was involved. Timing is informational; the
regression checks values and the external-parser budget, not wall time.

Run the focused regression and benchmark with:

```bash
bash tools/scripts/stopwatch_proc_stat_selftest.sh --bench
bash tools/scripts/cold_start_to_tip_stopwatch.sh --selftest
```

The baseline was the working file before this slice, not pristine HEAD. Its
SHA-256 was `d4f37e624963a661b021521042114099261bb09c743673c3e5b87eec8fc59bf0`.
Temporary baseline source and test snapshots are retained for this session in
`/tmp/worldstream-proc-builtins/before.sh` and `test-before.sh`; run the latter
with `--bench /tmp/worldstream-proc-builtins/before.sh` to repeat the original
measurement. They are not repository artifacts.

The expanded regression covers decimal leading zeros, exact CPU addition
above 2^53, signed 64-bit bounds, overflow rejection and independent missing
fields, alongside the existing process-name, whitespace and caller tests.
The old parser fails the new exact-addition case: `9007199254740993 + 1`
produces `9007199254740992`, rather than `9007199254740994`. A mutation selecting
the wrong CPU field also fails. The large-counter checks qualify the parser;
they do not extend the downstream CPU-seconds conversion's arithmetic range.

Validation passed: focused regression and benchmark, the complete cold-start
stopwatch selftest, artifact-symmetry selftest, Bash syntax, pipefail-status,
discarded-status, shell-host-assumption and architecture-tree checks, and
`git diff --check`. ShellCheck is unavailable. `make lint-fast` did not finish
within a 45-second bound, so no complete lint pass is claimed. The flag-registry
gate still reports 17 stale pointers in other already-modified files; this
script's four pointers were refreshed. No full node build or live sync
acceptance was performed.

Consensus and cryptographic validation, optional acceleration behavior,
Hetzner-owned scheduling and database/runtime code are unchanged. The exact
slice contains no secrets, logs, binaries, caches or generated build output.

Publication remains blocked: `.git` is read-only, and origin access cannot
resolve `github.com`. No commit, push or remote-SHA verification is claimed.
