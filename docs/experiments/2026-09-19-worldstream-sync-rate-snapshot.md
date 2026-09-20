<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: derive sync rates from the captured timing sample

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The checkout already contained extensive
unrelated staged and unstaged work; this slice owns only the sync telemetry
provider, its standalone regression, and this record.

## Bottleneck and witness

The sync telemetry provider collects six stage timing EWMAs, then reads the
same live counters eight more times to derive two rates and the slowest stage.
These redundant reads cost observer work during synchronization and can make
the derived fields disagree with the published timing fields. The field
contract describes the rates as derived from those published values.

On this x86_64 AMD EPYC 7402P host (48 logical CPUs), a deterministic fixture
seeds the snapshot with a slowest stage of `body_fetch`, 1000 microseconds,
then makes live getters return newer, changing values. The unchanged source
reports eight additional reads and `tip_finalize`, 900006 microseconds; the
regression exits 1. The changed source reports zero additional reads and
`body_fetch`, 1000 microseconds; the regression passes with GCC 14.2 and
Clang 20 at C23, `-O2 -Wall -Wextra -Werror`.

Total EWMA reads per full collection fall from 14 to 6. This is an exact
operation-count measurement, not a wall-clock or end-to-end IBD speed claim.
The fixture uses no peers, datadir, cache, or live chain. It also checks both
rates, derived provenance, equal maxima, nonpositive timings, unavailable
metadata, and the one-microsecond boundary. Stage samples are still captured
sequentially; this change does not claim an atomic snapshot of the ladder.

## Change and reproduction

`fill_rate` now reuses the six values already captured by `fill_headers`,
`fill_bodies`, and `fill_apply`. Rate arithmetic, stage order, tie handling,
and unavailable-state rules are unchanged. The regression compiles the real
rate function with the real generated snapshot types and scalar metadata
setters, stubbing live getters, the clock, and text-copy support. Source
extraction refuses missing or duplicate boundaries.

```sh
git show c1f7863d098e1efaa8deba240c580ae0559312a5:engine/services/src/sync_telemetry_fill.c > /tmp/sync-rate-before.c
# Expected failure: eight redundant reads and a different slowest stage.
bash tools/scripts/sync_telemetry_rate_selftest.sh /tmp/sync-rate-before.c
ANALYZE=1 bash tools/scripts/sync_telemetry_rate_selftest.sh
CC=clang-20 bash tools/scripts/sync_telemetry_rate_selftest.sh
```

## Validation and limits

The standalone regression passes on both compilers. The complete provider
translation unit compiles with C23 warnings as errors; GCC `-fanalyzer` and
Clang `--analyze` report no diagnostics. The shell parses with `bash -n`.
Telemetry ontology coverage and its 13-case selftest pass. The existing lint
runner passes all seven selected gates: architecture tree, nonblocking
dumpers, telemetry ontology, pipefail status pipes, allocation checks, raw
allocation checks, and log-macro return types. `git diff --check` passes.

The normal registered `telemetry_sync` groups and full lint were attempted.
The normal build encountered a missing Tor dependency and a read-only
`.git/config` during submodule registration. Separate attempts with the
documented offline development Tor stub each exceeded a 120-second bound
after template generation (exit 124), without test or lint verdicts. These
are incomplete broader checks, not passes; no full-node acceptance is claimed.

There are no changes to consensus, validation, header admission, request
scheduling, database tuning, wallet custody, or node lifecycle behavior.
Z23 acceleration remains optional and independent validation authoritative.
Only source, the regression script, and this experiment record belong to the
slice; no benchmark output or build artifacts belong in its commit.
