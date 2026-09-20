<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: avoid rescanning quiet seed-readiness logs

The cold-start-to-tip probe scanned its complete log on every pending seed
observation, even when no bytes changed. Reuse a no-match observation only
while the file's device, inode, size, mtime and ctime remain equal. Capture
metadata before reading so a concurrent append is eligible on the next poll.
Check the independent install marker before the cache. Reader or metadata
failure, a symlink, or the coarse BSD metadata fallback cannot establish a
reusable miss. Readiness still requires the existing marker or RPC evidence.

Reuse the probe's fixture metadata operation through `probe_file_metadata`.
Its BSD fallback preserves fixture size and epoch mtime, but disables the
log cache. Existing size thresholds and fixture ordering remain unchanged.
The fallback is tested with a command double; no native macOS run is claimed.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with substantial pre-existing edits.
Pre-slice `tools/scripts/cold_start_to_tip_probe.sh` SHA-256:
`482b4ef02aeb6b0555b5a270fb4a1eff5f6c9feb4d8d4e5d57d8276712c48469`.
After this slice:
`a2b535fd5a491f2b4fb2db537cfe4a58089ca70d64908744e3cb90b95c651062`.
These identify file bytes, not published commits.

Measured on Linux x86_64, AMD EPYC 7402P, Bash and GNU tools, ambient load,
warm ordinary filesystem cache. The isolated fixture contains 16 MiB of
newline-delimited diagnostics without a seed marker. Each trial invokes the
actual observer twenty times, without a node, network or production datadir.

| Measurement | Before | After |
|---|---:|---:|
| Full scans, 20 quiet polls | 20 | 1 |
| Quiet trial 1 | 203 ms | 86 ms |
| Quiet trial 2 | 208 ms | 83 ms |
| Quiet trial 3 | 208 ms | 84 ms |
| Growing log, 20 polls | 211 ms | 287 ms |

Quiet-log median observer time falls about 60%. A growing log still requires
twenty scans and pays about 3.8 ms extra per poll for metadata in this sample.
This is a tradeoff for quiet startup intervals, not an end-to-end IBD speedup.
The regression gates scan counts and behavior, never wall-clock timings.
The original source fails the new quiet-log scan-count assertion (20 vs 1).

Reproduce without live fixtures:

```bash
bash tools/scripts/cold_start_seed_idle_selftest.sh
bash tools/scripts/cold_start_seed_idle_selftest.sh --baseline /path/to/before.sh
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
bash tools/scripts/cold_start_snapshot_metadata_selftest.sh
bash tools/scripts/cold_start_snapshot_metadata_selftest.sh --cold-start
bash tools/scripts/cold_start_timing_selftest.sh
```

All pass. Coverage includes both bundle modes, partial and concurrent append,
truncation, replacement, same-inode rewrite with restored mtime, linked logs,
binary bytes, independent marker arrival, mode changes, reader failure and
unavailable/coarse metadata. The regression is registered in the probe's
existing `--selftest`; two existing extraction fixtures load the shared helper.
Existing snapshot-selection and startup timing assertions remain intact.

Bash syntax, shell-host-assumptions, architecture-tree, pipefail-status and
discarded-status checks pass, as do staged and unstaged `git diff --check`.
The new untracked test was also explicitly scanned by the shell status gates.
No compiled source changed; ShellCheck is unavailable. Aggregate `make
lint-fast` timed out after 55 seconds during prerequisite preparation. The
Make selftest invocation was interrupted during preparation; its component
scripts passed directly. Aggregate integration acceptance remains incomplete.

Only the probe, extraction fixtures, new regression and this record belong to
this slice. Consensus, validation, optional acceleration policy, wallet state,
node runtime and Hetzner-owned work are unchanged. No secrets, generated files,
logs, binaries, caches or production state belong in the proposed change.

Publication is blocked: `.git` is mounted read-only, preventing fetch/commit,
and the origin lookup cannot resolve GitHub. No commit, push or remote-SHA
verification is claimed. The branch is unchanged; prior staged and unstaged
work is preserved. The isolated patch and raw fixture results are under
`/tmp/worldstream-seed-idle/` for review.
