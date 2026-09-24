# Worldstream rolling log

## 2026-09-24T20:55:34Z

- Measured problem: `-reindex -prune` ignored stale `blk*.dat` and `rev*.dat` deletion failures.
- Baseline: `CleanupBlockRevFiles()` was `void` and reindex continued after unsuccessful cleanup.
- Root cause: filesystem removal results were discarded, leaving possible stale files outside rebuilt metadata.
- Files changed: `src/init.cpp`, `src/util.h`, `src/util.cpp`, `src/test/util_tests.cpp`, `doc/storage-reliability.md`.
- Validation: daemon and Boost test binary rebuilt; utility suite passed 27 cases including successful stale-file removal and deterministic `/proc` removal failure; main, coins, DB-wrapper, and PoW groups passed; `git diff --check` passed; cleanup McCabe complexity is 10 and `RemoveFile` is 2.
- Consensus impact: NONE.
- Commit SHA: `ba1e6ac2daaa0a663929a8a9d5b52ae9bab6d231`.
- Remote SHA: `ba1e6ac2daaa0a663929a8a9d5b52ae9bab6d231` on `development/dev/ibd-performance-20260918`.
- Next investigation: measure shutdown-time PID-file removal and block-prune deletion handling; refresh Hetzner before implementation.

## 2026-09-24T20:42:58Z

- Measured problem: POSIX startup PID-file creation ignored open, write, and close failures.
- Baseline: `CreatePidFile()` returned no status and `AppInit2()` continued without process-ownership metadata.
- Root cause: PID-file durability was outside the startup error path.
- Files changed: `src/util.h`, `src/util.cpp`, `src/init.cpp`, `src/test/util_tests.cpp`, `doc/storage-reliability.md`.
- Validation: daemon and test binary rebuilt; utility tests passed 26 cases including `/dev/full` close failure; main, coins, database-wrapper, PoW, and transaction groups passed; `git diff --check` passed; no consensus code or networking code changed.
- Consensus impact: NONE.
- Commit SHA: `aeb52c062b70aa00939628c2831e07060304d48d`.
- Remote SHA: `aeb52c062b70aa00939628c2831e07060304d48d` on `development/dev/ibd-performance-20260918`.
- Next investigation: measure startup cleanup and stale block-file removal failures during interrupted reindex; refresh Hetzner first.

## 2026-09-24T19:31:48Z

- Measured problem: block and undo file pre-allocation failures were discarded.
- Baseline: `AllocateFileRange()` returned `void`; callers continued after platform allocation, open, or close errors.
- Root cause: storage error results were not part of the block-position write path.
- Files changed: `src/util.h`, `src/util.cpp`, `src/main.cpp`, `src/test/util_tests.cpp`, `doc/storage-reliability.md`.
- Validation: daemon and test binary built with the documented rustzcash archive route; focused utility, main, coins, and database-wrapper groups passed 44 cases; complete suite reached one unrelated nondeterministic `addrman_sparse_selection` failure, then that test passed in isolation; `git diff --check` passed; McCabe complexity is 4 (`PreAllocateFileRange`), 16 (`FindBlockPos`), 6 (`FindUndoPos`), and 2 (`AllocateFileRange`).
- Consensus impact: NONE.
- Commit SHA: `101128ae2550c63d51eb809414fe5b9dd02ed5ed`.
- Remote SHA: `101128ae2550c63d51eb809414fe5b9dd02ed5ed` on `development/dev/ibd-performance-20260918`.
- Next investigation: measure startup/restart metadata recovery for interrupted block-file growth; first refresh and inspect Hetzner's latest networking branch.
