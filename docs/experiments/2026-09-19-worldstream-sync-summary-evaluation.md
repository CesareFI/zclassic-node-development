<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream sync-summary evaluation cost

`ops.telemetry.sync.summary` evaluated its full snapshot in `tls_prepare`,
discarded that verdict, then evaluated it again inside the renderer. The first
pass allocated a complete JSON value plane and visited every ontology rule.
The summary now leaves judgement to the existing renderer. Both stage
projection commands retain their separate verdicts. No provider, rule, view,
reply budget, consensus predicate, validation path, or acceleration policy changes.

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. The command source was clean before this slice;
all pre-existing staged and unstaged work is separate. Owned files are the
command source, `tools/scripts/telemetry_sync_summary_selftest.sh`, and this note.

The fixture compiles the actual command, schema, renderer, fitting ladder,
ontology evaluator, JSON implementation and allocation-fault machinery. Only
the snapshot provider, clock, network selection and reply transport are fixture
implementations. It opens no datadir, starts no node and contacts no peers.
This is observer-overhead evidence, not measured end-to-end IBD acceleration.

On Linux x86_64, AMD EPYC 7402P (48 logical CPUs), GCC 14.2.0,
`-std=c23 -O2 -Wall -Wextra -Werror`, three alternating baseline/updated runs
with warm caches and uncontrolled host load measured:

| 5,000 summary calls | Baseline | Updated |
|---|---:|---:|
| Redundant full evaluations | 5,000 | 0 |
| Wall ms, pair 1 | 658.341 | 362.467 |
| Wall ms, pair 2 | 661.330 | 356.196 |
| Wall ms, pair 3 | 652.928 | 365.793 |
| Median wall ms | 658.341 | 362.467 |

The median reduction is 44.9%. Timing excludes compilation. The regression
asserts evaluation count and behavior, not a timing threshold. The baseline
fails the new zero-redundancy assertion without `--baseline`.

Successful replies and next-action hints compare byte-for-byte for twelve
cases: healthy, ladder inversion and missing-field snapshots, each at summary,
normal, full and unrecognized views. Health remains `ok`, `degraded` and
`unknown` respectively. Provider failure, oversized provenance, allocation
failure and both stage commands are exercised. Allocation failure still
refuses with an explanatory error; the summary now reports `RENDER_FAILED`
instead of the discarded preliminary pass's `EVALUATE_FAILED`.

Reproduce from this checkout (scratch output only):

```sh
bash tools/scripts/telemetry_sync_summary_selftest.sh
ANALYZE=1 bash tools/scripts/telemetry_sync_summary_selftest.sh
SANITIZE=1 ASAN_OPTIONS=detect_leaks=0 bash tools/scripts/telemetry_sync_summary_selftest.sh
scratch=$(mktemp -d /tmp/z23-summary-comparison.XXXXXX)
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/command/native_telemetry_sync_command.c > "$scratch/baseline.c"
BENCH_ROUNDS=5000 OUTPUT="$scratch/before" bash tools/scripts/telemetry_sync_summary_selftest.sh --baseline "$scratch/baseline.c"
BENCH_ROUNDS=5000 OUTPUT="$scratch/after" bash tools/scripts/telemetry_sync_summary_selftest.sh
cmp "$scratch/before" "$scratch/after"
```

Strict compilation, GCC `-fanalyzer`, ASan and UBSan pass. LeakSanitizer cannot
operate under this environment's tracing, so leak detection is explicitly
excluded from the successful sanitizer run. Shell syntax and `git diff --check`
pass. The core seal matches all 554 files and 80 sections; no core file differs
from HEAD. Scoped architecture, file-size, shell-host assumptions, pipefail,
discarded-status, no-Python and no-API-keys lint pass (seven scoped gates).

Broader `make t-fast ONLY=telemetry_sync` selected the two registered sync
telemetry groups but could not reach execution: Tor bootstrap attempts to write
read-only `.git/config`. `make lint-fast` also remained in preparation. Both
were bounded to 55 seconds; neither is reported green.

Publication is blocked: Git metadata is mounted read-only, and GitHub remote
queries fail DNS resolution. No commit, push or remote-SHA verification is
claimed. The required development branch is unchanged. Temporary binaries,
benchmark output and logs are confined to `/tmp` or ignored build state.
