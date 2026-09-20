<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: release the sync-counter mutex before receipt serialization

Scope: performance instrumentation in `sync_benchmark_service.c`. A receipt
request previously held the mutex shared by download counters and phase stamps
through JSON allocation, object copying and formatting. Hardware discovery had
already been moved outside that mutex by pending Worldstream work; this slice
preserves that work and removes the remaining serialization contention.

The service now copies its fixed-size measurement state under the mutex and
serializes that private observation afterward. The mutex itself is separate
from the copyable state. Every writer retains its original locking and update
behavior. Timing fields, resource counters, artifact identity and null reasons
all use the same captured state; later updates appear in the next receipt.

## Baseline and measurement

Checkout HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The baseline is the existing dirty service,
not pristine HEAD. Service SHA-256 before this slice:
`50f2c644fa8a4d60017937ca173968f90e9039d4e4a4edf418d385d969b163e1`.
After this slice:
`f720d989f0456517ef7815636037a313563c0beb1f082d28db896b38f92fb6d7`.

Environment: Linux x86_64, GCC 14.2.0, C23, `-O2 -Wall -Wextra -Werror`,
real in-tree JSON library, warm process/allocator, ambient host load. No node,
network, production state, downloaded packages or real chain data are used.
The fixture substitutes only clock/hardware/build identity observations and
omits durable filesystem publication. The measured workload serializes 10,000
incomplete receipts with one recorded download counter per run. Mutex hold time
is measured between successful lock acquisition and release, using monotonic
clock calls; the after figure includes their measurement overhead.

| Measurement | Before | After |
|---|---:|---:|
| Excluded writer attempts during two receipt serializations | 16 / 16 | 0 / 16 |
| Mutex held, run 1, ms / 10,000 receipts | 36.313 | 0.589 |
| Mutex held, run 2, ms / 10,000 receipts | 36.339 | 0.541 |
| Mutex held, run 3, ms / 10,000 receipts | 36.218 | 0.532 |
| Total wall time, median ms / 10,000 receipts | 55.201 | 56.694 |

Median mutex occupancy falls by about 98.5%. Receipt wall time does not improve
in this experiment. These measurements establish less instrument contention;
they do not establish an end-to-end IBD or time-to-tip improvement.

## Reproduction and regression

```bash
bash tools/scripts/sync_benchmark_receipt_snapshot_selftest.sh --bench --analyze
bash tools/scripts/sync_benchmark_receipt_snapshot_selftest.sh --baseline --bench /path/to/before.c
make sync-benchmark-receipt-lock-selftest
```

The new fixture intercepts integer emission during the real receipt builder.
It checks mutex availability and invokes real counter, phase and milestone
writers at that point. The first receipt must retain all original values; the
next receipt must contain all admitted changes. Complete and incomplete receipt
paths are both exercised. The test has no timing-dependent pass threshold.
The unchanged baseline fails the zero-exclusion assertion. A mutant reading
`bytes_reused` from live state instead of the captured state fails the original
receipt's value assertion. The optional timing loop is informational.

The existing hardware-observation fixture supports both mutex layouts and
still passes its six receipts, missing/zero RAM cases, field and null checks.
Both fixtures run through the existing Makefile receipt-lock target, which is
already a dependency of the fresh-sync benchmark and its test aggregate.

## Validation and publication limits

Passed: both focused fixtures, GCC `-fanalyzer`, whole-service syntax checks,
shell syntax, `git diff --check`, and exact slice diff inspection. Direct calls
to the available lint binary passed architecture and shell-host-assumption
checks. The available core-seal checker verified all 554 sealed files and 80
sections; no `core/` path differs from HEAD.

`make t-fast ONLY=sync_service` selected the sync-service and snapshot-sync
service groups, but Tor preparation failed to register its submodule because
`.git/config` is read-only. The full lint and make-driven architecture/seal
attempts did not finish prerequisite work and were interrupted. The available
checker binaries were then used for the bounded checks above; they do not
substitute for a completed fresh-build lint or registered test run.

Publication is incomplete: fetching cannot write `.git/FETCH_HEAD`, and
`git ls-remote origin` cannot resolve GitHub. No commit or push was made and no
remote SHA was verified. The original staged/unstaged work is preserved. This
slice adds only source, a regression/benchmark, its Makefile invocation, the
existing fixture's mutex-layout compatibility, and this experiment record.
Temporary binaries and measurement output stay outside the proposed files.

No consensus predicate, validation, optional-acceleration policy, peer/request
scheduling, database behavior, or production state is changed. Full integration
and publication remain required on a writable, dependency-equipped checkout.
