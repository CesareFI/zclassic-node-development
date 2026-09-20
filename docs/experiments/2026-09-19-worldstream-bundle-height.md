<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream bundle-height selection overhead

Branch: `agent/worldstream-ibd-20260918`; base HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.
This slice changes only the cold-start probe's bundle-height return mechanism,
adds a regression to its existing Make target, and records this evidence.
Earlier staged, unstaged and untracked work is preserved.

The selector already avoided unnecessary metadata commands, but still spawned
one command-substitution shell for every eligible bundle name. The parser now
assigns the caller's output variable with Bash `printf -v`. Numeric ranking,
fallback names, size eligibility, failed markers and tie order are unchanged.

Local Linux x86_64 / Bash fixture: 100 sparse bundle files in descending height
order, five selections per trial, three trials, uncontrolled ambient load.
The new regression instruments the actual parser's process identity:

| Trial | Before (seconds) | After (seconds) |
|---|---:|---:|
| 1 | 0.705 | 0.098 |
| 2 | 0.693 | 0.085 |
| 3 | 0.698 | 0.069 |

Across 1,500 parser calls, child-shell calls fall from 1,500 to zero. The
existing uninstrumented bundle-name regression also preserves its winner:
five-selection median falls from 0.629 to 0.080 seconds. These are benchmark
fixture-selection costs, not measured end-to-end IBD or time-to-tip gains.
No node, network, wallet or production datadir participates in these tests.

Reproduction:

```bash
bash tools/scripts/cold_start_bundle_height_selftest.sh --baseline /path/to/before.sh
bash tools/scripts/cold_start_bundle_height_selftest.sh
bash tools/scripts/cold_start_bundle_rank_selftest.sh --bench
bash tools/scripts/cold_start_bundle_name_selftest.sh
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
```

The new regression fails against the pre-change source because height parsing
forks. It passes after the change, including canonical, zero-padded, empty,
malformed and fallback names and silent output-variable assignment. Existing
bundle rank (14 scenarios), bundle name, both snapshot-metadata modes, and the
probe's complete hermetic selftest pass. Bash syntax, architecture-tree,
discarded-status, pipefail-status and shell-host checks pass. Tracked-tree lint
scans do not cover the new untracked regression; it was separately inspected,
parsed and executed. No compiled code changes; ShellCheck is unavailable.
`git diff --check` passes. The exact incremental source and Make diffs were
reviewed against copies taken before this slice.

`make cold-start-snapshot-metadata-selftest` and `make lint` each exceed a
50-second bound during setup, before reporting results. Their direct focused
scripts pass as stated above; the complete Make/lint gates remain unverified.
No validation threshold was changed. Consensus and reducer paths match HEAD;
acceleration policy, node runtime, peer scheduling and database code are untouched.

Publication remains blocked: `.git/FETCH_HEAD` is read-only, `origin/main` is
absent locally, and the origin host cannot resolve for remote SHA inspection.
No commit, push, upstream integration or independent remote SHA verification
is claimed. Only the two source/test files, Make invocation and this note belong
to the slice; fixture output and saved baselines remain outside the repository.

Pre-change probe SHA-256:
`49dab4e24d299fcf2f20cf95523261d053bd2646d171107fd1a7785d6ae5f91b`.
Changed probe SHA-256:
`c483c8c5b7e8482bb5e230f6bc7d78c91cc51cd633c6697009ef05f91c52bbde`.
