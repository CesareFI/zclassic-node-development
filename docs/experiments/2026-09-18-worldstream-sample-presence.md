<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream stopwatch sample-presence cost

The artifact-symmetry checker counted every data row in each `samples.tsv`
only to test whether at least one existed. Each check launched awk and wc,
streaming the complete ledger through a pipe. The replacement uses one awk
process and stops after processing the second record. Header comparison and
all other evidence assertions remain unchanged.

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The checker was unchanged at entry; the
checkout contained unrelated unfinished Worldstream work, preserved here.
This slice owns only the checker, its new sample-presence selftest, and this
note. There are no consensus, node-runtime, scheduling, database, custody,
or optional-acceleration changes.

Measured on Linux x86_64, AMD EPYC 7402P, Bash 5.2.21, GNU awk 5.2.1.
The synthetic fixture contains a header and 1,000,000 rows (25,888,907 bytes).
The filesystem cache is warm and ambient host load is uncontrolled. There is
no node, datadir, peer, or network in the benchmark.

| Ten row-presence checks | Original predicate | Changed predicate |
|---|---:|---:|
| Wall time | 2.722 s | 0.028 s |
| User + system CPU | 3.171 s | 0.030 s |
| External processes per check | 2 | 1 |

This is a synthetic scaling measurement of evidence-checking overhead, not
an observed end-to-end IBD bottleneck or time-to-tip improvement. The normal
symmetry fixture is short; the million-row case stresses the comparison's
behavior on larger sample sets. Timing is informational, not a pass threshold.

Reproduce with:

```sh
bash tools/scripts/stopwatch_sample_presence_selftest.sh --bench
bash tools/scripts/stopwatch_artifact_symmetry_check.sh --selftest
```

The new test compares eight file cases with the original predicate: missing,
empty, header-only with and without newline, one row with and without newline,
blank row, and CRLF. A deterministic record-processing guard permits awk input
buffering but detects processing beyond the second record. Removing the early
exit makes this guard fail. GNU awk and mawk both pass, as do the existing
artifact-symmetry mutation checks, stopwatch judge, cold-start stopwatch, and
triple-run driver selftests. The new test runs through the existing symmetry
selftest entry point.

Shell syntax, architecture, shell host assumptions, discarded status,
pipefail-status-pipe, no-Python, no-API-keys, no-warning-suppression and
whitespace checks pass. The core seal verifies 554 files and 80 sections;
there is no diff under `core/`. No binaries, logs, generated artifacts,
credentials, or temporary benchmark output belong to this slice.

Full `make lint-fast` is not green: vendor preparation cannot resolve GitHub
or register the Tor submodule in read-only Git metadata, unrelated flag
first-use pointers are stale, and the Windows acceptance guard cannot create
its scratch directory outside the writable roots. Focused checks do not
substitute for those publication gates. No public-node build or live sync
acceptance is claimed.

Publication remains blocked: `.git` is read-only, `origin/main` is absent
locally, and `git ls-remote origin` fails on GitHub DNS. Commit, push, and
remote-SHA verification are not claimed. The development branch is unchanged.
