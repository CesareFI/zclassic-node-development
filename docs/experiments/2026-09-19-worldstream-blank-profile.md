<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reject blank fold-profile observations before further work

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold profiler accepted successful RPC output containing only spaces, tabs
or carriage returns. Its empty-string check missed these responses, so it
continued polling, parsed absent fields as zeros and appended an unusable CSV
sample. Such a row could replace the last usable observation in a sync summary.

The sampler now checks for non-whitespace text using a POSIX shell builtin
predicate before continuing. Each of its five required responses gets the
same check. Existing RPC failure diagnostics, CSV columns, missing-field
defaults within nonblank documents and acceptance thresholds are unchanged.
This is a presence check, not general JSON validation.

The existing RPC regression now covers 35 refusal cases, including spaces,
tabs, CR/LF and mixed ASCII whitespace at each endpoint. It verifies exact
RPC counts, unchanged CSV bytes, no observation formatting, failure context
and recovery with whitespace-padded nonblank telemetry. The entry implementation
fails the new test at `drive/success_spaces`, after five RPCs and an invalid row.

## Measurement

Linux x86_64, 48 reported logical CPUs, POSIX shell, warm tools/filesystem
caches, uncontrolled host load. Three sequential baseline/candidate pairs
each made 100 sampling attempts with a blank first RPC and synthetic nonblank
responses for later RPCs. RPC and parser wrappers counted actual invocations;
the timestamp was fixed. No node, network, real-chain data or datadir was used.

| Per 100 attempts | Entry implementation | Candidate |
|---|---:|---:|
| RPC invocations | 500 | 100 |
| External parser invocations | 500 | 0 |
| Unusable rows appended | 100 | 0 |
| Rejected attempts | 0 | 100 |
| Wall seconds, three trials | 2.73 / 2.72 / 2.70 | 0.07 / 0.07 / 0.07 |

These measure observer work on invalid input, not IBD throughput or time to tip.
At later failing endpoints the sampler preserves preceding required RPCs and
skips only subsequent work. Healthy samples still make all five RPCs.

## Reproduction and scope

Run `sh tools/scripts/fold_profile_rpc_selftest.sh [fold_profile.sh]` to reproduce
the refusal and exact RPC budget checks. Broader validation uses
`fold_profile_selftest.sh`, `fold_profile_scan_selftest.sh`,
`fold_profile_drive_selftest.sh`, `fold_profile_summary_selftest.sh` and
`fold_profile_history_selftest.sh` in the same directory. All passed. The RPC
regression also passed under Bash and BusyBox sh. POSIX/Bash syntax and the
architecture, shell-host-assumptions, pipefail-status and discarded-status
gates passed. `git diff --check` passed. `make lint-fast` timed out after
55 seconds during initialization; no aggregate lint pass is claimed.
ShellCheck and the public node binary are unavailable. No C changed; compiler
and live-chain tests do not apply to this isolated shell slice.

The baseline is the working file at entry, SHA-256
`1f45e676320b81d8140fd49657f1d69aa96bbc655ad614145d2680bcb1c8e34d`,
not pristine HEAD. The sampler and RPC test already contained earlier work;
do not stage their entire accumulated contents as this slice. Entry copies,
the measurement fixture and a separate incremental patch are retained under
`/tmp/worldstream-blank-profile/` as temporary development evidence.

Only the sampler, its RPC test and this note belong to this slice. Consensus,
cryptographic validation, optional acceleration policy and Hetzner-owned node
runtime, scheduling and database code are untouched. The incremental diff
contains no secrets, datadirs, logs, caches, binaries or generated output.

Publication remains incomplete: `.git/FETCH_HEAD` is read-only and the origin
branch lookup cannot resolve GitHub. No commit, push, integration with current
main or exact remote-SHA verification is claimed.
