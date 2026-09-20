<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound serial-benchmark topology discovery

Scope: startup of `tools/serial_bench.c`, the standalone block-deserialization
benchmark used to investigate IBD costs. This is benchmark tooling overhead,
not a measured improvement in node startup, parsing throughput or time to tip.

## Baseline and witness

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The working checkout contained unrelated
staged and unstaged changes. An isolated checkout at that commit qualified
only this slice; the original staged work was preserved byte for byte.

Host: Linux 6.8.0-139-generic, x86_64, AMD EPYC 7402P, 48 configured CPUs,
GCC 14.2.0. The measured topology helper was compiled with C23, `-O2`,
`-Wall -Wextra -Werror -pedantic`. Ordinary warm filesystem caches and ambient
host load apply. No node, datadir, chain corpus or peer was used.

The topology probe assigns domain indices in first-seen CPU order. After
finding the selected CPU's domain, it continued scanning the remaining CPUs,
although none could change that index. CPU 0 incurred two initial reads plus
48 scan reads on this host, even for CSV output that does not print topology.

| 2,000 CPU-0 topology probes | Before | After |
|---|---:|---:|
| sysfs open attempts | 100,000 | 6,000 |
| elapsed seconds | 1.073237 | 0.086616 |
| reported domain | 0 | 0 |
| reported L3 size | 16,384 KiB | 16,384 KiB |
| reported shared CPUs | 0-2,24-26 | 0-2,24-26 |

The benchmark counts actual `fopen` calls in the source helper; elapsed time
is informational. The deterministic regression's 64-CPU fixture failed on
the baseline with `cpu=0 reads=66 expected=3`.

## Change and validation

Stop the scan immediately after assigning the matching domain's index.
Missing topology, a failed CPU-count query, repeated domains, offline CPUs,
unavailable L3 size and the existing 16-domain bound retain their behavior.
The timed deserialization loop, affinity policy and all parity checks are
unchanged. No consensus, runtime, scheduling, database or optional-acceleration
code changes.

Reproduce the regression and host-specific measurement with:

```bash
bash tools/scripts/serial_bench_topology_selftest.sh
bash tools/scripts/serial_bench_topology_selftest.sh --bench
```

Both commands accept an optional final source-file path for baseline testing.
The regression is also wired as `make bench-serial-topology-selftest` and into
`make bench-serial-selftest`.

Validation completed:

- Baseline failure and candidate pass for all 64 selected fixture CPUs,
  missing size/count observations and the 16-domain boundary.
- `make bench-serial-topology-selftest` passed in the isolated checkout;
  Make also reported an unrelated unavailable zlib download during setup.
- The same regression under ASan/UBSan (leak detection disabled for this
  environment; this does not establish leak freedom).
- Standalone benchmark build with the Makefile's C23, `-O3`, x86-64-v3 and
  warning-as-error flags; GCC `-fanalyzer` compilation.
- Isolated benchmark parity self-check, plus the combined working-tree
  observation and corpus suites (4 incomplete-parse and 12 corpus refusals).
- All 32 `LINT_FAST_GATES` through the repository's `run_lint.sh` driver in
  the isolated checkout, using existing lint binaries. The Windows fixture
  used its supported `ZCL_WINDOWS_ACCEPTANCE_GUARD_SCRATCH=/tmp` override.
- Shell syntax, discarded-status, pipefail, architecture, core seal and
  `git diff --check`. All 554 sealed files and 80 sections match the seal.

The ordinary working-tree Make invocations stalled in prerequisites and were
interrupted. Standalone compilation and the direct lint driver supplied the
focused build and lint evidence above; no full-node build or IBD acceptance
is claimed. No generated files, logs, binaries, caches, credentials or temporary
benchmark output belong to this source slice.

## Publication boundary

The original checkout's Git metadata is read-only. The isolated writable
checkout retains the same development branch and contains only this slice.
Origin access initially failed because GitHub DNS could not resolve. A later
fetch succeeded and confirmed the development branch still matched the tested
baseline. Publication must use only that branch on origin and verify its exact
remote SHA; local validation alone does not establish publication.
