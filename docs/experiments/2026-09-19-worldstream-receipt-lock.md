<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: keep receipt hardware reads outside the sync counter lock

`sync_benchmark_build_receipt()` held the instrument mutex while discovering
physical cores and reading process/host memory. On Linux the memory adapter
reads procfs and cgroup files. Counter writers and phase stamps share that
mutex, so requesting a receipt excluded them throughout those independent
hardware observations.

The change samples those two hardware values before acquiring the instrument
mutex. The receipt keeps its existing field order, types, null handling and
locked snapshot of instrument state. Phase-boundary RSS sampling is unchanged.
There is no cached hardware value or new worker, API, dependency or wire format.

## Reproduction

The isolated fixture compiles the actual instrument state, receipt builder and
counter functions with the real JSON implementation. It substitutes only the
hardware and identity/clock providers and omits durable file publication.
During each hardware observation it probes the instrument mutex with
`pthread_mutex_trylock`; when available, it releases the probe lock and calls
the real download counter API. This is a deterministic lock-overlap witness,
not a simulated elapsed-time result or an end-to-end IBD speed claim.

```sh
bash tools/scripts/sync_benchmark_receipt_lock_selftest.sh --baseline /path/to/before.c
bash tools/scripts/sync_benchmark_receipt_lock_selftest.sh --analyze
make sync-benchmark-receipt-lock-selftest
make bench-fresh-sync-selftest
```

Six receipts cover complete/partial output with successful, failed and zero-RAM
observations. All 12 hardware observations excluded counter writers before the
change; none exclude them afterwards. The fixture checks actual counter updates,
phase duration, readiness and unmeasured sovereignty, artifact identity, hardware
fields, incomplete reasons and unmeasured resource nulls. Its default mode fails
on the pre-change source. No node, network, production datadir or credentials
participate. The Makefile registers it independently and in the existing
cold-start benchmark aggregate.

Observed environment: Linux 6.8.0-139-generic, x86_64, GCC 14.2.0, C23, `-O2`.
The fixture uses `-Wall -Wextra -Werror`, optionally runs GCC `-fanalyzer`, and
syntax-checks the complete production translation unit with the same warnings.

Source identities for `engine/services/src/sync_benchmark_service.c` (SHA-256):

- Before: `691964844334388e3e088c4a2477c0e8e831d02940657737dc306a7208db2399`
- After: `50f2c644fa8a4d60017937ca173968f90e9039d4e4a4edf418d385d969b163e1`
- Checkout HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`

## Validation and limits

The focused fixture, compiler static analysis, complete cold-start benchmark
fixture aggregate, shell syntax, architecture tree, discarded-status and
pipefail-status gates pass. Worktree and index `git diff --check` pass.
The core seal independently verifies all 554 files and 80 sections.

The registered `make -j2 t-fast ONLY=soak_attestation` attempt cannot establish
its required Tor dependency: submodule registration fails because `.git/config`
is read-only. The broader test and full `make lint` attempts are bounded to
120 seconds; neither produced a test/lint verdict. They remain unverified.
Native macOS and live time-to-tip performance were not measured. JSON receipt
construction and phase-boundary RSS sampling still hold the instrument mutex;
this change removes only the receipt's hardware observation from that interval.

Only sync performance instrumentation, its isolated regression, Makefile wiring
and this record belong to this slice. Consensus, validation, scheduling,
databases, optional acceleration and production state are unchanged.

The branch remains `agent/worldstream-ibd-20260918`. Pre-existing staged and
unstaged work is preserved. Fetch fails opening read-only `.git/FETCH_HEAD`,
and a read-only remote query fails resolving GitHub. No commit or push can be
completed here, and no remote SHA equality is claimed. This is a locally
qualified change awaiting the unavailable integration and publication steps.
