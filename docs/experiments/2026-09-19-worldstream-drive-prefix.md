<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: avoid rescanning fold-observer diagnostic prefixes

Branch: `agent/worldstream-ibd-20260918`; unchanged HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold profiler's `jnums` reader first located each requested literal key
with `index`, then repeated the search from the start of the entire response
line with a regex. Large diagnostic prefixes were therefore searched twice
per present column on every observation. The reader now starts the regex at
the already located key. It still searches the remaining suffix, preserving
malformed-occurrence handling and the last valid match on the first matching
line. Missing fields, duplicate requested columns, exact wide integer text,
stage triples and complete input draining retain their existing behavior.

This slice changes that reader, registers a new prefix-cost regression under
`make fold-profile-selftest`, and adds this note. Earlier staged, unstaged and
untracked work is preserved. The baseline is the working script at entry,
SHA-256 `d79effc4674a3fdf52a7598b69533a1f727ec576f93959452d46a46eebe646d9`,
not pristine HEAD. Baseline copies and an incremental slice patch are kept
under `/tmp/worldstream-drive-prefix/` as temporary development evidence.

## Measurement

Linux 6.8.0-139-generic x86_64, GNU awk 5.2.1, POSIX shell. Synthetic
responses contain 0, 500 or 50,000 diagnostic fields before scalar and stage
keys, followed by lines exercising malformed values and duplicate selection.
Each timing runs 100 uninstrumented reads, checking the exact CSV each time.
Three baseline/candidate pairs use warm tools with uncontrolled ambient host
load; the second pair overlapped bounded integration checks. No node, network,
peer, production datadir or real-chain trial participates.

| Measurement | Baseline | Candidate |
|---|---:|---:|
| Regex input bytes, 0 diagnostic fields | 1,593 | 1,353 |
| Regex input bytes, 500 diagnostic fields | 53,013 | 1,353 |
| Regex input bytes, 50,000 diagnostic fields | 6,140,533 | 1,353 |
| 100 small reads, median wall seconds | 0.47 | 0.47 |
| 100 medium reads, median wall seconds | 0.52 | 0.50 |
| 100 large reads, wall seconds | 4.97 / 4.90 / 4.82 | 3.07 / 3.09 / 3.06 |

The large-fixture median falls about 37%. The deterministic regression bounds
bytes handed to regex matching, not input transport or total parsing work:
the literal search must still visit the prefix. Regex call count remains 17.
This demonstrates reduced benchmark-observer cost, not faster end-to-end IBD
or a measured time-to-tip improvement.

Reproduce with:

```sh
sh tools/scripts/fold_profile_prefix_selftest.sh --baseline --bench /tmp/worldstream-drive-prefix/fold_profile.before.sh
sh tools/scripts/fold_profile_prefix_selftest.sh --bench
make fold-profile-selftest
```

## Validation and remaining limits

The baseline passes value checks and fails the new work bound. The candidate
passes with GNU awk, mawk and BusyBox awk. The canonical
`make fold-profile-selftest` target passes, including bootstrap/epoch fixtures,
exact CSV, sparse and malformed responses, duplicate selection, parser budgets,
and 35 failed/blank RPC scenarios with recovery. Separate counter, long-history
and summary tests pass across the available awk implementations.

POSIX shell and Bash syntax checks, architecture-tree, shell-host-assumption,
pipefail-status and discarded-status gates pass. `git diff --check` passes.
`make lint-fast` exceeded its 55-second bound after initialization; an aggregate
lint pass is not claimed. ShellCheck and the public node binary are unavailable.
No compiled source changed, so no compiler or live-chain validation is claimed.

The exact incremental diff was reviewed. Consensus, cryptographic validation,
optional acceleration policy, and Hetzner-owned scheduling, database and runtime
code are unchanged. No secrets, generated artifacts, logs, caches, binaries or
production data belong to this slice.

Publication remains incomplete. Retried fetch cannot write `.git/FETCH_HEAD`
because Git metadata is read-only; remote branch lookup cannot resolve GitHub.
No commit, push or local/remote SHA equality is claimed. The outstanding lint
check and publication restrictions must be resolved before publishing. Do not
stage the entire dirty Makefile or profiler as this slice: both contain earlier
work beyond the incremental patch.
