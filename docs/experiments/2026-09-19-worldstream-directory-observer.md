<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bounded directory-size observation

Branch: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The SLO probe samples datadir size through `evidence_dir_bytes`. Each sample
started awk to read one integer from `du -sb`. More seriously, it retained
that integer when the traversal failed or timed out after printing a partial
total. The reader's existing contract says those cases are unmeasured.

The change checks the bounded traversal's status before accepting its output,
then extracts the first field using Bash builtins. Successful zero and wide
integer values remain exact text; absent observations remain empty with a
successful reader status. The traversal, timeout, measurement cadence and
apparent-byte definition are unchanged. This also affects the shared reader's
worktree-GC consumer; no GC operation was run.

## Baseline and measurement

Baseline: the working library at entry, SHA-256
`7d7012e15a51915135576ddd2b56d26dbd4c8570a1192e9104f676b8c2071cc7`.
Its directory-size function was unchanged from HEAD. Earlier modifications
elsewhere in that library and the Makefile remain separate work.

Linux x86_64, Bash 5.2.21, GNU coreutils 9.4, ordinary warm caches. Each
measurement performs 500 real bounded directory traversals of a private
fixture containing one small file. Three consecutive baseline/candidate pairs
ran on the same host; concurrent lint and test activity was not controlled.
No node, production datadir, peer or network participated.

| Measurement | Baseline | Candidate |
|---|---:|---:|
| Wall seconds, run 1 | 3.167 | 2.970 |
| Wall seconds, run 2 | 3.197 | 2.967 |
| Wall seconds, run 3 | 3.193 | 2.737 |
| External parsers per sample | 1 | 0 |

Median observer time fell from 3.193 to 2.967 seconds, about 7%. This is an
observer-cost result, not an IBD/time-to-tip speedup. Large datadir traversal
cost remains and can dominate the saved process startup.

## Regression and validation

The new test exercises the actual reader against private fixtures and a fake
`du`, retaining the real timeout wrapper. Baseline fails on nonzero traversal
status, simulated timeout status, and an actual timeout after partial output.
It also violates the zero-parser budget. Candidate passes those cases plus
zero, wide integers, whitespace, a filename containing a newline, malformed
and missing data, a missing tool, changed caller IFS, and disabled pipefail.
An ordinary real `du` result must match byte-for-byte. The test is registered
in the existing `evidence-selftest` target.

```sh
bash tools/scripts/evidence_dir_bytes_selftest.sh --bench
bash tools/scripts/node_slo_probe.sh --selftest
```

The complete `evidence-selftest` recipe passed using a temporary Makefile
containing the exact recipe extracted from the working Makefile, avoiding
unrelated global build initialization. Existing RSS, peer-count, JSON-reader
and string-reader tests also passed. The final expanded focused test passed.
Bash syntax, architecture-tree, shell-host-assumption, discarded-status and
pipefail-status gates passed. `git diff --check` passed. No C source changed;
compiler/chain tests were not run and ShellCheck is unavailable.

`make lint-fast` exceeded a 60-second bound during initialization. Running
its full declared gate list through the native lint driver completed with
four failures: the existing `.agents`/`.codex` root entries, complexity in
the previously modified `bench_fresh_sync.c`, stale flag-registry line
pointers, and an unwritable default Windows-guard scratch directory. The
Windows guard subsequently passed its selftest and scan using its supported
scratch override under `/tmp`. The other failures remain; no aggregate
lint pass is claimed and no baseline or assertion was weakened.

## Scope and publication

This slice owns only the directory-size function, its new test and Makefile
registration, and this note. Consensus, cryptographic validation, optional
acceleration, and Hetzner-owned scheduling/database/runtime code are unchanged.
The slice contains no secrets, logs, generated files, caches or binaries.
The existing Git index was compared byte-for-byte through its cached diff
and preserved. Temporary evidence and an isolated patch live under
`/tmp/worldstream-dir-observer/` and are not intended for commit.

Publication is blocked. `origin/main` is absent. Fetch of the authorized
development branch cannot write `.git/FETCH_HEAD`; even `git add --dry-run`
cannot create `.git/index.lock` on the read-only filesystem. Two remote-branch
lookups failed to resolve GitHub. No commit, push or remote-SHA verification
was completed. Do not commit the whole dirty library or Makefile as this
slice, since both contain earlier work.
