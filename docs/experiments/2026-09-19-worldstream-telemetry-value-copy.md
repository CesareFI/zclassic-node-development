<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: avoid copying the telemetry evaluation value tree

Scope: IBD observation overhead, outside peer scheduling, request recovery and
storage tuning. Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`.

`telemetry_evaluate()` builds the full value plane, then `json_push_kv()` deep
copies it beneath `values` solely to give the read-only ontology evaluator its
expected root. Each sync poll pays for that redundant copy; render calls also
use this evaluation path.

The evaluator now uses a stack root borrowing the already-built value plane.
Only the owning value plane is freed, after all evaluation and scalar finding
copies finish. Offset checks, complete-domain evaluation, ratio operands,
health rules, output filtering and missing-observation handling are unchanged.
There is no cross-poll cache or mutable shared state.

## Measurement

Measured on Linux x86-64, AMD EPYC 7402P, GCC 14.2.0, C23 `-O2`, using the
standalone fixture below with a fully populated sync snapshot. These are warm,
in-process synthetic observations, with no node, network or production datadir.
CPU affinity was not pinned; concurrent host load was not controlled.

| Work over 20,000 evaluations | Before | After |
|---|---:|---:|
| Full value-tree copies | 20,000 | 0 |
| Checked buffer allocation attempts | 960,000 | 640,000 |
| Observed elapsed milliseconds | 1107.413 | 1158.432 |

The deterministic saving is 16 buffer allocation attempts per evaluation
(48 to 32, one third). The existing allocation hook counts malloc/calloc/realloc,
not strdup; omitted key/string copies are not counted as measured allocations.
Elapsed samples do **not** establish a speedup. No end-to-end IBD improvement is
claimed. A controlled time-to-tip run remains necessary to quantify user impact.

## Reproduction and validation

```sh
git show c1f7863d098e1efaa8deba240c580ae0559312a5:platform/modules/util/src/telemetry_render.c > /tmp/telemetry-render-before.c
CC=gcc-14 BENCH_ROUNDS=20000 OUTPUT=/tmp/telemetry-before.jsonl bash tools/scripts/telemetry_evaluation_copy_selftest.sh --baseline /tmp/telemetry-render-before.c
CC=gcc-14 BENCH_ROUNDS=20000 OUTPUT=/tmp/telemetry-after.jsonl ANALYZE=1 bash tools/scripts/telemetry_evaluation_copy_selftest.sh
cmp /tmp/telemetry-before.jsonl /tmp/telemetry-after.jsonl
CC=clang-20 SANITIZE=1 ASAN_OPTIONS=detect_leaks=0 bash tools/scripts/telemetry_evaluation_copy_selftest.sh
```

The fixture compiles the actual renderer, JSON implementation, ontology and
schemas. It executes the existing `telemetry_render` and `telemetry_ontology`
test bodies, plus all registered domains across every presence state, view and
group. The 570 serialized documents match byte for byte. Injected allocation
failure still refuses evaluation, and the zero-copy assertion fails against the
baseline when `--baseline` is omitted.

GCC warnings as errors and `-fanalyzer` passed. Clang AddressSanitizer and UBSan
passed. LeakSanitizer was unavailable under this environment's tracing, so the
successful sanitizer run explicitly disabled leak detection.

`make lint-fast` passed all 32 gates with
`ZCL_WINDOWS_ACCEPTANCE_GUARD_SCRATCH=/tmp/worldstream-telemetry-gate-scratch`;
the default scratch directory is outside the writable roots. Core seal,
architecture tree, telemetry ontology and `git diff --check` passed.
The canonical `make t-fast ONLY=telemetry_render` could not complete because
required vendor downloads cannot resolve GitHub. The standalone test results
above do not claim a full-node suite pass.

No consensus, validation, chain-state, wallet or acceleration-policy source
changes. Normal independent validation remains authoritative; optional Z23
acceleration remains optional. No benchmark output or generated binary belongs
in this change.
