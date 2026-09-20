<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: cold-boot proof polling cost

Scope: `fresh-boot-weld-prove.sh`'s H* sample extraction only. The existing
reader starts two `grep` processes and one `head` per sample. This slice uses
POSIX shell builtins and preserves the first numeric match, line boundaries,
negative sentinels, textual wide integers, and success/missing exit status.
The driver still observes checkpoint landing and subsequent H* climb with the
same deadlines, retry policy, and verdict predicates.

Baseline source: `c1f7863d098e1efaa8deba240c580ae0559312a5`. Measured locally
on 2026-09-18, Linux x86_64, 48 online CPUs, Bash 5.2.21. Each warm-process
benchmark performs 1,000 command-substitution extractions of the same compact
frontier fixture. Three consecutive runs per implementation, no network,
node, datadir, or chain cache involved:

| Reader | Wall seconds, three runs | Median | Parser commands/sample |
| --- | --- | --- | --- |
| Original | 4.473, 4.389, 4.426 | 4.426 | 3 |
| Builtins | 1.329, 1.353, 1.340 | 1.340 | 0 |

The median fixture cost fell approximately 70%. This is observer overhead,
not a live IBD or time-to-tip speedup. Network, validation, and database costs
are unmeasured here. An intermediate one-awk implementation was discarded
because it reduced CPU use but regressed wall time (median 4.830 seconds).

Reproduce the benchmark and regression:

```sh
bash tools/scripts/fresh_boot_weld_parser_selftest.sh --bench
bash tools/scripts/fresh-boot-weld-prove-selftest.sh
```

The parser test accepts an optional source-script path after `--bench` for
baseline comparison. It extracts only the reader definition, never runs the
live driver's entry point, and checks 22 input cases under both `sh` and Bash.
The original reader passes value/status checks but fails the deterministic
process-cost gate (six external parser invocations for two samples; now zero).
The existing driver selftest invokes this regression before its 11 hermetic
boot/verdict scenarios. No assertion is graded on elapsed time.

Validation: all 44 parser value/status checks and the process-cost gate;
all 11 hermetic driver scenarios (74 seconds); shell syntax;
shell-host-assumptions, discarded-status and pipefail-status gates; consensus
seal (554 files and 80 sections). The change touches shell instrumentation
and tests only. No consensus, chain serialization, cryptography, validation,
runtime scheduling, database behavior, or optional-acceleration policy changes.

Broader environment limits: `make z23` cannot fetch missing vendor archives
in the restricted environment. `make lint-fast` passes 28/32 gates; remaining
failures are the pre-existing `.agents`/`.codex` root entries, pre-existing
`bench_fresh_sync.c` complexity growth, stale flag-registry pointers in other
dirty files, and a Windows guard attempting to write outside writable roots.
Those files and thresholds are preserved. ShellCheck is unavailable; shell
syntax and in-tree static gates were used. No temporary output or build
artifacts belong to this slice.
