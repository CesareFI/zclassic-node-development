<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: avoid rescanning unchanged IBD boot logs

The stopwatch's `refresh_boot_observation` reread the complete node log every
poll, even when no bytes had changed. This slice caches the parsed observation
under the log path and the existing file-metadata helper's device, inode,
extent, mtime and ctime stamp. Metadata is sampled before scanning. Appends,
replacement, truncation and rewrites invalidate the entry. Symlinks, coarse or
failed metadata, and failed scans do not establish reusable entries. Cached
facts still pass through the original boot-count and respawn classification.

This is shell benchmark instrumentation only. It changes no consensus,
validation, acceleration settings, peer scheduling, database or node runtime.
It neither runs a node nor establishes an end-to-end IBD improvement.

## Measurement

Linux x86_64, 48 online CPUs, Bash 5.2.21, warm ordinary filesystem caches,
ambient host load. The fixture observes a 16 MiB newline-delimited log with
boot and respawn markers, 20 times per trial. Three trials:

| Measurement | Before | After (final candidate) |
|---|---:|---:|
| Full scans per 20 polls | 20 | 1 |
| Wall seconds | 1.726 / 1.740 / 1.756 | 0.164 / 0.167 / 0.167 |
| User seconds | 1.448 / 1.435 / 1.459 | 0.094 / 0.097 / 0.087 |
| System seconds | 0.215 / 0.243 / 0.234 | 0.075 / 0.075 / 0.085 |

Changing logs still require a scan on every poll. Incremental scanning of
growing logs remains a possible next bottleneck, requiring separate evidence.

## Reproduction and validation

Run `bash tools/scripts/stopwatch_boot_idle_selftest.sh`. It covers invalidation,
cached-fact application, concurrent appends, failed reads, unusable metadata,
symlink targets and the unchanged/growing scan budgets. Passing an older
stopwatch path runs the same regression against it; `--baseline` before that
path records the timing without enforcing the new unchanged-log scan ceiling.
The pre-change source passes the observation checks and fails the ceiling
with 20 scans instead of one.

`bash tools/scripts/cold_start_to_tip_stopwatch.sh --selftest` passes, including
218 existing `ok` assertions and its nested fixtures. Shell syntax,
pipefail-status-pipe and shell-host-assumption gates (including their selftests)
pass. `git diff --check` passes. ShellCheck is unavailable. `make lint-fast`
was interrupted before producing a gate verdict; broader lint is incomplete.

The checkout was already extensively dirty at
`c1f7863d098e1efaa8deba240c580ae0559312a5`; that commit alone is not the measured
baseline. The pre-change stopwatch SHA-256 is
`47a28b715921b98774cf68b3b29800cdcc848de23603a2bbb58413b8f406161e`;
the final candidate is
`4efc47f0d61384698d03f70caa63eb03834c8188f467b2068aec2ec9be6b3b62`.
The shared metadata library, unchanged by this slice, is
`22d697042e699ee78b0009177864c88f2c68e8bb01bc8240413f2e420ebcbb0a`.
Existing changes remain separate and must not be swept into a future commit.

Publication is unavailable in this session: Git refuses `.git/index.lock`
and `.git/FETCH_HEAD` on the read-only Git metadata directory; remote queries
also fail to resolve GitHub. No commit or push is claimed, and no remote SHA
was verified. The branch remains `agent/worldstream-ibd-20260918`.
