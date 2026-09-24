# Worldstream rolling log

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
