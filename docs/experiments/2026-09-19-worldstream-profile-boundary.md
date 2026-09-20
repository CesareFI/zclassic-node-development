<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: skip delimiter-free profile prefixes in bulk

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold telemetry reader's `jnums1` checked a counter's preceding field
boundary one character at a time. Long delimiter-free diagnostic prefixes
therefore consumed substantial observer CPU even after locating the requested
key. It now skips 128-byte spans containing neither a quote nor a comma,
then retains the existing character check near the delimiter. Nearest-quote
rejection, nearest-comma admission, first integer selection, missing zeros,
duplicate requested keys and exact wide integer text remain unchanged.

The baseline is the working script at entry, SHA-256
`354e064e3a8509a4d5d4ec02c8ffe25658ba9871dbf06518978cc2eb0c4a9a61`,
including earlier pending work. This slice adds ten lines to that reader,
adds a focused benchmark/regression, invokes it from the existing scan
selftest, and adds this record. Earlier staged and unstaged work is preserved.
Entry snapshots and a slice patch are under
`/tmp/worldstream-profile-boundary/`; they are temporary development evidence.

## Measurement

Linux x86_64, GNU awk 5.2.1, POSIX shell, warm tools/filesystem caches,
uncontrolled ambient host load. Three sequential baseline/candidate pairs
read synthetic responses twenty times each. No node, RPC, production datadir
or peer participates. This measures observer overhead, not real IBD throughput
or time to tip.

| Prefix / measurement | Baseline | Candidate |
|---|---:|---:|
| 16-byte prefix, wall seconds | 0.09 / 0.09 / 0.09 | 0.09 / 0.09 / 0.09 |
| 1 MiB prefix, wall seconds | 4.96 / 4.95 / 4.96 | 0.48 / 0.49 / 0.48 |
| 1 MiB prefix, character probes per read | 1,048,578 | 8,194 |

Median stress-fixture wall time falls about 90%. Total scanning still scales
with prefix length; the improvement removes most interpreted character steps.
These synthetic prefixes do not establish their frequency in live telemetry.

Reproduce with:

```sh
sh tools/scripts/fold_profile_boundary_selftest.sh --bench
sh tools/scripts/fold_profile_boundary_selftest.sh --baseline --bench /path/to/baseline.sh
```

The baseline fails the new deterministic work bound. The regression checks
44 nearest-delimiter fixtures around chunk boundaries, two measured prefix
sizes, duplicated and absent requested keys, and exact wide values. Timing is
reported, not used as a pass threshold. The existing scan selftest now runs
the regression automatically.

## Validation and limits

- The scan suite and new regression pass under GNU awk, mawk and BusyBox awk.
- Broader fold-profile CSV, RPC refusal/recovery, drive, summary, missing-key
  and counter-prefix regressions pass. RPC coverage includes 35 refusals.
- POSIX/Bash syntax, discarded-status, pipefail-status, shell-host-assumption
  and native architecture gates pass. Repository shell gates scan tracked
  files; the new script also receives explicit syntax checking and execution.
- `git diff --check` passes. Exact slice diffs were inspected; the entry
  staged diff remains byte-for-byte unchanged. No compiled code changed.
- `make lint-fast` exceeded a 50-second bound during initialization. No
  aggregate lint or public-node acceptance pass is claimed.

Consensus, independent validation, optional acceleration policy, custody and
Hetzner-owned scheduling/database/runtime code are unchanged. This slice
contains only shell source and this document: no secrets, logs, binaries,
caches, generated output or production state.

Publication is incomplete. Fetch cannot write `.git/FETCH_HEAD`; staging the
new regression cannot create `.git/index.lock` because Git metadata is
read-only. Origin lookup also fails to resolve GitHub. No commit, push,
upstream integration or remote-SHA verification is claimed. The branch is
unchanged. Do not stage the whole dirty reader or scan selftest as this slice;
both contain earlier work. Aggregate lint remains an outstanding gate.
