<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: preserve wide counts in fold bottleneck reports

Branch: `agent/worldstream-ibd-20260918`; HEAD at entry:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold profiler retained wide durations but still formatted stage calls,
advances, batches, barriers and proof-operation counts with awk `%d`. BusyBox
awk 1.36.1 narrows these to signed 32-bit integers: a synthetic delta of
2,147,483,648 appeared as -2,147,483,648 in 31 summary fields. Such reports
cannot reliably describe the work behind an IBD bottleneck. This is a proven
instrumentation defect, not evidence of a live node reaching those counts.

The fix uses `%.0f` for summary counts and interval integers, preserving the
existing column widths, endpoint arithmetic, CSV schema and per-work ratios.
It does not change counter collection or introduce full-history parsing.
Awk floating-point precision remains a limit; this does not promise exact
arithmetic for arbitrary 64-bit counters.

## Baseline and measurement

The baseline is the working script at entry, SHA-256
`1303ae9a8e7cc551eab15b9746e824974397646554a0c69588c32ad358b597f7`.
It includes earlier uncommitted work. The slice changes only formatting and
its explanatory comments in that script, adds a regression to the existing
`fold-profile-summary-selftest` Make target, and adds this note.
Do not stage the whole profiler or Makefile as this slice. The baseline and isolated patch
are under `/tmp/worldstream-profile-counts/`, outside committed evidence.

Linux x86_64, GNU awk 5.2.1, warm filesystem caches, uncontrolled ambient load;
all inputs are synthetic and use no node, network or production datadir.
The existing history benchmark summarizes a 7,000,799-byte CSV with 10,000
samples twenty times per trial. Three baseline trials took 0.28/0.29/0.29
seconds; three candidate trials took 0.29/0.29/0.28 seconds. Both medians were
0.29 seconds. This establishes no speedup or end-to-end time-to-tip claim.

## Validation

`sh tools/scripts/fold_profile_counts_selftest.sh` checks 31 count fields at
100, 2^31-1, 2^31, 2^32 and 2^40, with nonzero initial counters and per-advance
ratios. The entry baseline fails at 2^31 under BusyBox awk; the candidate
passes under GNU awk, mawk and BusyBox awk. These are formatter regression
fixtures, not recorded chain activity.

`make fold-profile-summary-selftest` passes, including its existing bootstrap
and epoch prerequisites (43 and 46 cases), wide durations, wide counts and
long-history summaries.

The existing profiler summary, history, sampler, RPC-refusal, drive,
sparse-drive, missing-key and scan selftests also pass. These cover idle and
absent measurements, exact CSV output, 35 RPC refusals and recovery, and
observer-work budgets. POSIX-shell and Bash syntax, architecture-tree,
shell-host-assumption, pipefail-status and discarded-status gates pass.
`git diff --check` passes. ShellCheck and the public node binary are absent;
no compiled code changed, so compiler and live-chain tests are inapplicable
to this formatting slice. Both `make lint-fast` and `make lint` exceeded
50-second bounds during initialization; no aggregate lint pass is claimed.

Consensus, validation, optional acceleration and Hetzner-owned scheduling,
database and runtime behavior are unchanged. No secrets, generated files,
logs, caches or binaries belong to this slice. Existing staged and unstaged
work is preserved.

Publication remains incomplete: `.git` is read-only, preventing Git metadata
updates, and GitHub DNS resolution fails. No commit, push or remote-SHA
verification is claimed. The unchanged local HEAD is not proof of publication
of this slice.
