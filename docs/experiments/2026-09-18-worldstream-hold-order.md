<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream post-sync observer ordering cost

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`,
`tools/scripts/slo_hold_judge.sh`, Linux x86_64, AMD EPYC 7402P,
Bash 5.2.21. The stable-at-tip observer insertion-sorted every sample before
evaluating its window. A synthetic 72-hour ledger at the shipped 60-second
cadence contains 4,320 rows; reversing their order reproduced quadratic work.
This is an adverse ordering fixture, not evidence of a reordered live ledger.

The replacement is a stable bottom-up merge sort. Already ordered adjacent
runs skip copying, preserving linear work on chronological input. Worst-case
sorting work becomes O(n log n), with O(n) additional scratch storage. All
four sample columns move together. Equal timestamps retain append order;
conflicting samples remain visible. Window selection, thresholds, verdicts,
recording and diagnostic fields are unchanged.

| 4,320-row fixture | Baseline wall | Changed wall |
|---|---:|---:|
| Chronological | 0.298 s | 0.299 s |
| Reverse chronological | 5.107 s | 0.350 s |
| Older and newer halves exchanged | 2.688 s | 0.310 s |

Each timing includes launching the real judge and parsing the complete
fixture, with warm filesystem caches and ambient host load. Inputs are local;
no network, RPC, node or datadir is involved. These observations describe
instrumentation overhead, not an end-to-end IBD or time-to-tip improvement.
Timing is informational and is never a pass threshold.

Reproduce from the repository root:

```sh
baseline=$(mktemp /tmp/zcl-hold-baseline.XXXXXX)
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/slo_hold_judge.sh > "$baseline"
bash tools/scripts/slo_hold_order_selftest.sh --bench "$baseline"
rm -f "$baseline"
bash tools/scripts/slo_hold_judge.sh --selftest
```

The ordering regression compares complete output and exit status against
independently stable-sorted input in 37 cases: healthy progress, excessive
gap, outage, regression, null counters, timestamp ties, pages, four input
orders and lengths around merge boundaries. With a baseline script supplied,
that script evaluates the sorted reference. The existing judge selftest
invokes these checks alongside its acceptance and record-mode cases.

The 37 comparisons pass under both mawk and gawk. A mutation that reverses
the merge tie preference fails the reverse-order timestamp-tie case. The
hold judge, tip-agreement judge and stall-pager selftests also pass from an
isolated checkout containing only this slice. Shell syntax, whitespace,
architecture, the consensus seal, shell host assumptions, POSIX ERE,
no-Python, no-API-key and no-warning-suppression checks pass.

Only observer tooling and this experiment record change. Consensus,
cryptographic validation, optional acceleration, peer scheduling and database
behavior remain unchanged. The consensus seal and scoped source checks are
separate evidence; the public-node build and full build-dependent lint require
vendor archives that this environment could not fetch because GitHub DNS was
unavailable.
