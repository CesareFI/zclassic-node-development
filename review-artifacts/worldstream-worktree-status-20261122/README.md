# Worktree cleanup reports an unavailable status count

| Identity | Git object |
|---|---|
| Candidate | `16ba4ded5f21f42c48f02b08e7b96ca269d0451c` |
| Base and bundle prerequisite | `0fc3c2d38d98cc4e50d0782d22c8bd51228a7c67` |
| Reviewed tree | `c90a21dbe8f95e3ff801721469ffce7769993c0b` |

When Git cannot inspect a worktree, `ops host gc` keeps it for review. Its review row now reports `dirty_count: -1`. Previously, a failed status command produced a count of zero. The correction changes the report and documents the sentinel. The cleanup decision and authority are unchanged.

The earlier branch cleanup correction by Rhett Creighton was already present in this base. This Worldstream contribution addresses a separate reporting defect. [Scoped reconciliation](evidence/scope.json)

## Reproduction

An isolated, non-root Linux CLI fixture created two disposable worktrees. One held an untracked note and had a synthetic corrupt Git index. The second was clean and idle. Both preview and apply reported zero for the first lane on the base and minus one on the candidate. Apply preserved both files byte-for-byte and removed the eligible checkout while retaining its branch. Each call used one explicit synthetic pool and a private process namespace. [Original result](evidence/before.json) · [Candidate result](evidence/after.json) · [Fixture](evidence/fixture.sh)

## Qualification and review

**Local disposition: HOLD for full-suite acceptance.** The native reproduction and independent static review passed. The required full gate returned `agent-verify: FAILED (t-fast-exact)`. Lint preflight, capability closure, file size, complexity, and lint-fast passed.

The focused run of `test_host_gc` and `test_host_gc_branch` exercised active and locked work, pending changes, protected paths, symlink handling, and eligible removal. The focused run executed 2 groups, with 0 cached, 0 failed and 0 self-skips. Changed-file verification executed 1609 groups, with 0 cached, 8 failed, 31 self-skips and 8 unobserved. The selector gated out 16 other groups. Six previously failing groups passed on focused fixture retries, all six executed with zero cached, failures or self-skips. The outstanding groups are `test_mesh_terminal_worker` and `test_mesh_terminal_hub`. The admitted worker’s no-op user/PID namespace probe exited 1 at the UID map with `Operation not permitted`. An independently admitted lane with this namespace capability must verify those groups. The original universal result stands. [Commands and actual receipts](evidence/qualification.json) · [Exact-candidate independent review](evidence/independent-review.txt)

The native package precheck skipped `check-core-seal` and recorded `proof-history: land state unavailable`. Scope was Linux synthetic workspaces. Windows runtime, native receiver verification, R1 acceptance and landing were outside this local qualification. The bundle and untouched generated offer passed a fresh local import. [Package verification](evidence/package-check.json)

## Artifacts

| Filename | Bytes | SHA-256 |
|---|---:|---|
| [worktree-status.bundle](worktree-status.bundle) | 1976 | `b6b73df598b32b013be04746925ff623ebdacff02daa8f0f254fa040f06597b5` |
| [worktree-status.patch](worktree-status.patch) | 4936 | `e2d3b6e75d234e94bb13d4a5e01f36d2749c5772881c91b434142b36d305def3` |
| [worktree-status-evidence.tar.gz](worktree-status-evidence.tar.gz) | 7405 | `99b22fe09abb5040fd4a6ecf732016d122d6653ec32886dee5470bf8ba33f424` |

## Changed paths

- `docs/dev/HOST_GC.md`
- `engine/composition/commands/ops.def`
- `tests/harness/src/test_host_gc_branch.c`
- `tools/command/host_gc_sweep.c`
- `tools/command/host_gc_sweep.h`
