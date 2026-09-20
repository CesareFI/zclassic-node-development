<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream instant-on copy-proof observer

The instant-on copy proof launched `sed` and `head` for each height sample
during tail catch-up. Its parser now uses the copy profiler's existing POSIX
sed print-and-quit idiom, retaining the same regular expressions, first
matching line, last integer result on that line, and exact height text.
The checkpoint, strict climb requirement, timeout, RPC calls, optional
acceleration, and normal independent validation are unchanged.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The subject script was clean
before this slice; other pending Worldstream work was preserved.
Baseline script SHA-256:
`10b354a5b0a5066fb7b135db82932d396f1afa3ea157d7a7570e859ce7bb2de6`.
Updated script SHA-256:
`86d043fcd32ee7bc03a28913eee9bdd1ac4a67aaf5fc81f79e50024e51c483a7`.

Reproduce with no node, network, wallet, or datadir:

```sh
sh tools/scripts/instant_on_tip_selftest.sh
/usr/bin/time -f 'wall=%e user=%U sys=%S' sh tools/scripts/instant_on_tip_selftest.sh --bench
make instant-on-tip-selftest
```

An optional final harness path selects a saved baseline. Both versions pass
29 output/status fixtures, including multiline, missing, duplicate, negative,
wide and leading-zero heights. The baseline fails the deterministic process
budget: three representative reads launch six parsers; the update launches
three. The test checks output bytes, including newline behavior. It preserves
the existing scalar extraction grammar, not general JSON validation.

Five alternating baseline/updated trials on Linux x86_64, using `/bin/sh`,
600 parser reads per trial plus fixture checks, gave these median seconds:

| Version | Wall | User + system CPU |
|---|---:|---:|
| Baseline | 1.51 | 2.74 |
| Updated | 1.40 | 1.66 |

These are warm local observer measurements with synthetic responses and other
development checks running, not end-to-end IBD measurements. No timing
threshold gates the test; the deterministic improvement is one fewer external
process per height observation. The three-second polling cadence is unchanged.

The new fixture passes under dash and bash. Shell syntax checks, the existing
copy-profiler reader regression, triple-run stopwatch selftest, stopwatch judge,
artifact-symmetry suite, architecture gate and `git diff --check` pass.
The consensus seal verifies all 554 files and 80 sections. This slice changes
only the observer script, its fixture, one Make target and this note; no node,
consensus, peer scheduling, database, or custody implementation changes.

The shell-host assumptions, no-API-keys, no-Python and core-root mirror checks
also pass. `make instant-on-tip-selftest` and `make lint-fast` each exceeded a
50-second bound during setup before reaching their recipes; neither aggregate
is claimed green. Direct execution of the new selftest passes. The public node
binary is absent, so native navigation and live IBD were not exercised.

Publication is incomplete: Git metadata is read-only and querying origin fails
because GitHub DNS is unavailable. No commit, push, upstream integration or
remote-SHA equality is claimed. The pre-existing staged index is byte-for-byte
unchanged. No secrets, generated artifacts, binaries, datadirs, logs or
temporary benchmark output belong to this slice.
