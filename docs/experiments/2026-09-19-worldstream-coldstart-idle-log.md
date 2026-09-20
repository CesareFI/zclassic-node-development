<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: skip unchanged cold-start log misses

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The isolated cold-start fixture gate searched its entire node log once per
second while waiting for the seed-ready marker, including when the log had
not changed. On a synthetic 16 MiB startup log, twenty quiet observations
performed twenty full searches. The new regression fails the entry code's
one-search budget with `expected <1>, got <20>`.

`cold_start_test.sh` now reuses the existing `stopwatch_file_metadata` helper
to remember a failed search's file identity, size, mtime and ctime. The marker
is part of that cache key. Metadata is captured before searching, so an append
after the search remains visible next time. Missing/coarse metadata, symlinks
and grep errors do not suppress future reads. Successful matches are not
cached. The polling interval, deadline, node arguments, marker parsing and
UTXO threshold remain unchanged. Growing logs still require a search per poll
and now incur a metadata observation too.

## Measurement

Linux x86_64, AMD EPYC 7402P, Bash 5.2.21. Warm synthetic fixture, ordinary
filesystem cache, no cache dropping or controlled host load. Each trial makes
twenty observations of the same 16 MiB absent-marker log without poll sleeps.
Both versions use the regression's same grep-counting wrapper; wall times
include its overhead. No node, RPC, peer or production datadir participates.

| Measurement | Entry baseline | Candidate |
|---|---:|---:|
| Full log searches per twenty quiet polls | 20 | 1 |
| Wall seconds, three trials | 0.213 / 0.213 / 0.212 | 0.078 / 0.078 / 0.080 |
| Full log searches per twenty growing polls | 20 | 20 |

The quiet-log scan count falls 95%; measured median wall cost falls about 63%.
These results measure benchmark observer overhead, not end-to-end IBD or
time-to-tip improvement.

## Reproduction and validation

```sh
bash tools/scripts/cold_start_log_idle_selftest.sh
bash tools/scripts/cold_start_timing_selftest.sh
bash tools/scripts/cold_start_snapshot_metadata_selftest.sh --cold-start
bash tools/scripts/cold_start_seed_idle_selftest.sh
```

All pass. The new regression covers missing files, split markers, unterminated
lines, binary logs, truncation, replacement, same-inode rewrites with restored
mtime, reader errors, concurrent appends, marker changes, metadata failure,
coarse metadata, symlink target appends, both seed markers, and quiet/growing
scan budgets. The existing integration test still rejects observations at or
after the exclusive deadline and counts at or below the UTXO threshold. Its
isolated script copy now includes the shared metadata library.

The regression is wired into the existing `cold-start-timing-selftest` Make
target, already required by both cold-start entry targets. That Make invocation
and `make lint-fast` each exceeded a 50-second bound during initialization;
neither is claimed green. The two target scripts passed directly. Bash syntax,
shell-host-assumption, pipefail-status, discarded-status, architecture-tree
and `git diff --check` checks pass. ShellCheck is unavailable. No compiled
source changes, so compiler and live-chain checks are not applicable to this
slice. No full-node startup or chain-sync acceptance is claimed.

## Scope and publication

Earlier staged, unstaged and untracked work was preserved. The entry script's
SHA-256 was
`d4dee05d87c191c10812eedf5cb81bc2c1bd79a2eeb13ea37adee63a5312ca47`;
this working-tree baseline includes earlier changes and is not pristine HEAD.
The shared metadata helper and timing regression were already present work.
The slice adds the cache helper and loop call, one test dependency copy, one
Make recipe line, the idle-log regression and this record. Baseline copies and
the slice-only patch are temporary evidence in
`/tmp/worldstream-coldstart-idle/`. Do not stage whole dirty files as this slice.

Consensus, cryptographic validation, optional acceleration policy and all
Hetzner-owned scheduling, database and runtime surfaces are unchanged. The
reviewed slice contains no credentials, chain data, logs, binaries, caches or
generated output.

Publication is blocked: fetch cannot write `.git/FETCH_HEAD`, staging cannot
create `.git/index.lock` on the read-only Git directory, and origin lookup
cannot resolve `github.com`. No commit or push occurred, and no remote SHA
equality is claimed. The branch and HEAD remain as stated above. Aggregate
lint and remote integration remain outstanding as well.
