<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream snapshot-selection metadata cost

Branch: `agent/worldstream-ibd-20260918`. HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Existing staged and unstaged
work is preserved. The measured baseline is the working-tree probe on entry,
not clean HEAD. Linux x86_64, Bash 5.2.21, local sparse fixtures with warm
ordinary filesystem caches and uncontrolled ambient load. No node, network,
wallet, chain fixture or production datadir participates.

The cold-start-to-tip probe selected the newest eligible UTXO snapshot with
separate `stat` processes for size and modification time. It now requests both
fields in one command per candidate. Missing files, failed metadata reads,
the strict greater-than-10-MiB floor, newest-mtime selection and last-candidate
tie order retain their behavior. Both fields now come from the same metadata
observation; this does not bind the subsequently copied file against changes.
Normal independent validation and optional acceleration policy are unchanged.

Each timing run selects from 100 sparse files ten times and asserts the exact
winner. Process counting is included in both timings. Fixture creation is
outside the timed region.

| Measurement | Before | After |
|---|---:|---:|
| Metadata commands per ten selections | 2,000 | 1,000 |
| Run 1, seconds | 7.452 | 3.874 |
| Run 2, seconds | 7.593 | 3.822 |
| Run 3, seconds | 7.600 | 3.894 |
| Median, seconds | 7.593 | 3.874 |

The fixture median decreases about 49%. This is benchmark setup overhead;
snapshot selection precedes the probe's node-launch stopwatch. It is not an
end-to-end IBD or time-to-tip gain, and 100 retained candidates is a synthetic
workload, not a measured inventory of this server.

Reproduce:

```bash
bash tools/scripts/cold_start_snapshot_metadata_selftest.sh --bench
# Optional last argument: a saved pre-change cold_start_to_tip_probe.sh.
make cold-start-snapshot-metadata-selftest
```

The baseline passes selection assertions and fails the one-command budget.
The changed selector passes both, including absent/refused metadata, empty
lists, boundary sizes, timestamp zero, filenames with spaces and reversed tie
order. Replacing `>=` with `>` fails the timestamp-zero assertion. Applying
only the selector patch to the clean HEAD probe also passes the new regression,
showing that it does not depend on the earlier dirty probe changes.

The existing probe selftest, tip-height parser, seed-log observer and startup
timing regressions pass. Bash syntax, architecture-tree, shell-host-assumption,
discarded-status, pipefail-status and core-seal-root-mirror checks pass.
The host-assumption inventory shrinks by the removed `stat` call. Index-based
lint does not cover the new untracked test; its syntax and execution were
checked directly. ShellCheck is unavailable. No compiled source changes.
Both `make cold-start-snapshot-metadata-selftest` and `make -j4 lint-fast`
exceed a 50-second bound during setup, before a test/lint verdict. Aggregate
validation remains incomplete; no node-build or full-lint pass is claimed.

Owned changes are the selector, one Make test target and its prerequisite,
the shrinking lint inventory row, the new regression and this note. The exact
incremental diff was inspected and `git diff --check` passes. The pre-existing
index is byte-identical by exported patch comparison. No secrets, generated
artifacts, logs, caches, binaries or temporary output belong to the slice.
Consensus source has no diff; node runtime, peer/request scheduling, database
behavior and validation semantics remain unchanged.

Baseline probe SHA-256:
`5a14bcb044e4d55c18dc430c249935ad12c6fd31c04455560de45ced9bc6ecfb`.
Changed probe SHA-256:
`71a88a682859311d880cb81275f27ef4bb7ba637b245ca76d0bb9fa0033ee0f9`.

Publication remains incomplete: `.git` is read-only, so fetching cannot write
`FETCH_HEAD`; `origin/main` is absent locally, and querying origin fails to
resolve GitHub. No commit, push or independent remote-SHA verification is
claimed. Before publication, separate this slice from earlier dirty work,
finish aggregate validation and integrate current upstream with working
origin access and writable Git metadata. Temporary baselines and the isolated
selector patch reside under `/tmp/worldstream-snapshot-metadata/`.
