<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: sparse fold-drive observation

Scope: external IBD performance instrumentation in `tools/scripts/fold_profile.sh`.
No node runtime, peer scheduling, database, consensus, validation or optional
acceleration behavior changes. No node or production datadir was used.

The branch is `agent/worldstream-ibd-20260918`, with HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The starting checkout already had
extensive uncommitted Worldstream changes, including the batched `jnums`
reader. This experiment compares against that working file, **not pristine
HEAD**. Its SHA-256 was
`036b0a90f8b62f2de928460101d85a4b0c9ad8f423f5601f86a004b9ab6bcff7`;
the resulting file is
`1303ae9a8e7cc551eab15b9746e824974397646554a0c69588c32ad358b597f7`.

The reader searched a complete diagnostic line with a regex for every missing
scalar or stage. A synthetic 1,227,855-byte response with 50,000 diagnostic
fields and just two requested columns incurred 18 regex calls. A literal-key
precheck now avoids the 14 searches for absent columns. Existing regexes still
decide values, including malformed fields, stage triples, last-valid-match on
the first matching line, missing-value zeros and exact wide integer text.

Measurements on Linux x86_64, AMD EPYC 7402P, dash and GNU Awk 5.2.1:

| Fixture | Before | After |
|---|---:|---:|
| Regex calls per sparse drive read | 18 | 4 |
| 30 sparse reads, elapsed | 2.19 s | 1.71 s |
| 30 sparse reads, user + system CPU | 2.33 s | 1.86 s |
| 200 complete sampler observations, elapsed | 5.02 s | 5.09 s |

These are single before/after observations with warm ordinary tool/filesystem
caches and uncontrolled host load. Timings use the uninstrumented reader;
the test asserts operation counts rather than elapsed time. The complete
sampler comparison uses the existing `fold_profile_drive_selftest.sh --bench`
fixture. This establishes a synthetic observer-cost reduction, not measured
node throughput or end-to-end time-to-tip improvement.

Reproduce:

```sh
sh tools/scripts/fold_profile_drive_sparse_selftest.sh --bench
make -j2 fold-profile-selftest fold-profile-summary-selftest
```

The new selftest accepts an optional final path to a baseline script;
`--baseline --bench` reports its measurements without imposing the new work
budget. Without `--baseline`, the starting reader fails at 18 versus 4 calls.
Removing the precheck from the changed reader also fails that assertion.

Both Make suites pass, including CSV, RPC refusal, duplicate/malformed input,
input draining, sparse profiles, long-history summaries and bootstrap timing
fixtures. The new regression and complete-drive fixture also pass under mawk,
GNU awk and BusyBox awk. Dash/Bash syntax and `git diff --check` pass.
Direct native lint checks for architecture, shell host assumptions and Python
exclusion pass, as does the shell pipefail-status gate. The staged diff and
the unrelated tracked working diff compare byte-for-byte equal to their
pre-edit captures.

The incremental slice contains the literal-key precheck, one Make test entry,
the new regression and this record. Earlier dirty work remains separate.
No secrets, generated outputs, binaries, caches or benchmark logs belong to
this slice. The consensus core has no staged or unstaged changes.

Publication remains incomplete: fetching fails because `.git/FETCH_HEAD` is
read-only, and a read-only remote query fails resolving GitHub. No commit or
push was made and no remote SHA was verified. The public build cannot register
the missing Tor submodule because `.git/config` is read-only; its bounded
attempt timed out after 45 seconds. `make lint-fast` timed out after 50 seconds
before a verdict. Neither attempt is passing integration evidence.
