<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fold-profile history summary cost

This slice reduces offline analysis overhead in `tools/scripts/fold_profile.sh`.
The summary uses the first and last cumulative observations, but previously
split every CSV row and copied all 50 columns into the last-observation array.
It now retains the two endpoint records, counts every sample, and splits only
the endpoints. The sampler writes a fixed 50-column schema. Summary text,
counter differences, shares, and per-block calculations remain unchanged for
these sampler-produced records. This is not a malformed-CSV repair facility.

The checkout was on `agent/worldstream-ibd-20260918` at
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with substantial pre-existing
staged and unstaged work. The benchmark baseline is the session-entry working
copy, including that earlier work, not a clean HEAD:

- Baseline profiler SHA-256:
  `c3a09b8d7f9e97769fd03dca181df3fc7fb58c4d4dab0dc7769cb3f087a6959f`.
- Revised profiler SHA-256:
  `06f036e9d721821069d9cee89127010bdbc6f18f1f5b8d26de411e0d23e6e813`.

Linux x86_64, AMD EPYC 7402P, GNU awk 5.2.1; ordinary warm filesystem caches
and ambient host load. The fixture contains 10,000 samples, 50 columns and
7,000,799 bytes, representing roughly 83 hours at the default 30-second
cadence. No node, peer, production state or real chain measurement is involved.

| Twenty summaries of the same fixture | Before | After |
|---|---:|---:|
| Wall time | 2.15 s | 0.28 s |
| User CPU | 2.05 s | 0.17 s |
| System CPU | 0.09 s | 0.10 s |

The approximately 7.7x result measures summary generation only. It establishes
no end-to-end IBD or time-to-tip improvement. All rows are still read; retained
data is bounded to two records. Elapsed time is informational, not a flaky
test threshold.

Reproduce:

```sh
sh tools/scripts/fold_profile_history_selftest.sh --bench
# Optional final argument selects a saved baseline fold_profile.sh.
make fold-profile-summary-selftest ARGS=--bench
```

The new test compares complete summary output from the long history with the
same two endpoint records, normalizing only the asserted sample count. It also
checks explicit stage deltas and an unterminated final record. GNU awk,
BusyBox awk and mawk pass. A mutation retaining the first sample as the last
fails. Existing wide-duration, empty/one-sample, idle, CSV reader, RPC refusal,
scan and drive tests all pass via their direct shell entrypoints. Shell syntax,
architecture, shell-host-assumption, discarded-status and pipefail-status
checks pass; the new untracked test also passed an explicit discarded-status
scan. ShellCheck is unavailable. No compiled code changed.

The `make` test/check wrappers and full lint attempt were interrupted during
prerequisites before producing their results; direct tests above do not imply
full lint passed. The node build encountered read-only Git metadata while
initializing the missing Tor submodule and was interrupted. Full build and
publication evidence remain incomplete.

Owned changes are the summary's endpoint buffering, one new selftest, one
additional recipe line in the existing summary selftest target, and this note.
Prior working-tree changes are preserved. No consensus, validation, optional
acceleration, peer scheduling, database or runtime code changes. No credentials,
logs, datadirs, caches, binaries or temporary benchmark output are included.

Publication is blocked: `.git` is read-only, and `git ls-remote origin` fails
to resolve GitHub. No commit or push was made, and the exact remote SHA could
not be verified. The development branch is unchanged. A subsequent authorized
run must review only this slice against the existing dirty work, rerun required
integration gates, and publish solely to the requested development branch.
