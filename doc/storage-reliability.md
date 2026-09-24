# Storage reliability

## Reindex stale-file removal failures (2026-09-24)

`-reindex -prune` previously ignored every stale `blk*.dat` and `rev*.dat`
deletion result. A failed removal could leave files that were absent from the
rebuilt metadata, wasting disk space and invalidating the storage assumptions
used by the resumed import. Cleanup now uses a checked removal helper and
fails startup before reindexing if the directory scan or any deletion fails.
The Linux regression covers successful block/undo removal and a deterministic
filesystem removal failure. This path performs no rename or fsync; those
failure paths are not involved. Consensus, chain history, validation, PoW,
monetary policy, and upgrade behavior are unchanged.

## PID-file failure propagation (2026-09-24)

Startup previously ignored failures while creating, writing, or closing the
POSIX PID file. The daemon could therefore continue without durable process
ownership metadata. `CreatePidFile()` now returns its combined result and
initialization fails with a clear error when the PID file cannot be completed.
A Linux `/dev/full` regression covers close failure. This changes startup
error handling only; consensus, chain history, transaction validity, PoW,
monetary policy, and upgrade behavior are unchanged.

## Pre-allocation failure propagation (2026-09-24)

Block and undo growth asked `AllocateFileRange()` to reserve the next file
chunk, but the helper discarded every platform error. A failed
`posix_fallocate`, Windows file-extension call, macOS allocation/truncation, or
fallback write was therefore followed by dirty file metadata and continued
block processing.

The helper now returns success only when the platform reservation completes.
`FindBlockPos()` and `FindUndoPos()` also require the file open and close to
succeed before recording the allocation. A Linux `/dev/full` utility regression
proves the failure is observable. This changes local disk-failure handling only;
block bytes, serialization, transaction validation, chain selection, PoW,
monetary policy, upgrade activation, and all consensus behavior are unchanged.

## Block and undo file flush failures (2026-09-19)

Block-index durability depends on block and undo data reaching stable storage
before LevelDB records that reference those files are committed. The legacy
`FlushBlockFile()` discarded failures from truncation, `FileCommit()`, and
`fclose()`, so an I/O failure could still be followed by an index write or a
block-file rollover.

A focused handle finalizer now attempts truncation when requested, commits the
file, always closes it, and reports the combined result. Both block and undo
handles are attempted even if the first fails. `FlushStateToDisk()` aborts before
the block-index batch on failure, and `FindBlockPos()` aborts before advancing
`nLastBlockFile`. `FlushBlockFile()` decreases from McCabe complexity 5 to 4;
the finalizer measures 4. Each caller gains one required failure branch.

The daemon and Boost test binary rebuilt with the normal warning set. Focused
main, coins, database-wrapper, and block checks passed 20 cases and more than
47 million assertions. The complete Boost suite then passed all 384 cases and
142,367,185 assertions. The existing utility regressions cover successful
commit and buffered-flush failure; no fault-injection seam was added to the
block-storage API. `git diff --check` passed.

This changes local I/O failure handling and shutdown behavior only. Block and
undo serialization, chain history, proof of work, transaction and block
validity, cryptographic validation, and all consensus parameters are unchanged.

## Bootstrap import archival (2026-09-19)

After importing the legacy datadir `bootstrap.dat`, the import thread renames it
to `bootstrap.dat.old`. A failed rename was previously ignored, causing the node
to rescan the entire file on every later startup. The result is now checked and
logged so the operator can correct the filesystem condition. Import success is
preserved and the original file remains available for retry.

The logging branch is isolated in a score-2 helper, leaving `ThreadImport()` at
McCabe complexity 9. A filesystem regression verifies that `RenameOver()` moves
the source bytes and removes the source path. All 22 utility tests passed (280
assertions), the three main tests passed 46,067,601 assertions, and Valgrind
reported zero errors and no definite, indirect, or possible leaks for the
rename regression. The daemon and Boost test binary rebuilt successfully, and
`git diff --check` passed.

This changes diagnostics after legacy block import only. Block parsing,
validation, indexing, and consensus behavior are unchanged.

## Block writer close failures (2026-09-20)

`CAutoFile` previously discarded the return from `fclose()`. Block and undo
writers could therefore report success when buffered data failed during close,
allowing later index updates to reference incomplete records. Explicit
`CAutoFile::fclose()` now reports success, clears its pointer before calling
libc, and remains idempotent. Its destructor continues to provide nonthrowing
cleanup. The block and undo writers return failure when their explicit close
fails, using their existing caller error paths.

A Linux `/dev/full` regression verifies close-failure reporting, pointer
invalidation, and idempotent cleanup. The rename regression was also moved to a
unique temporary directory after the first full run exposed its dependence on
the shared test datadir lifetime. Focused utility, main, and coins groups passed;
the final complete Boost run passed all 386 cases and 141,725,857 assertions.
Valgrind reported zero errors and no definite, indirect, or possible leaks for
the close-failure regression. The daemon and test binary rebuilt with the normal
warning set, and `git diff --check` passed.

This changes write-error propagation only. Block and undo bytes, serialization,
validation order, chain selection, and consensus behavior are unchanged.

## Block position arithmetic (2026-09-20)

`FindBlockPos()` previously added an incoming serialized record size to the
current 32-bit file size before comparing with the 128 MiB block-file limit. A
wrapped sum could bypass rollover. Reindex positions also added their offset and
record size without checking the unsigned result. Input validation now rejects
records at least as large as a whole block file and rejects reindex positions
that cannot be represented. It also rejects a negative known/reindex file number
before conversion to the unsigned vector index. The rollover comparison uses
subtraction after the size check, avoiding overflow while preserving the
existing boundary behavior.

Validation runs before file metadata, file handles, or block accounting are
modified. Extracting it limits `FindBlockPos()` to McCabe complexity 16, one
required branch above its prior score; the validation helper measures 4. The
daemon and Boost test binary rebuilt successfully, and the focused main, coins,
and database-wrapper groups passed. The complete Boost suite then passed all 386
cases and 143,422,545 assertions. `git diff --check` passed. This changes
malformed local position handling only; accepted block serialization and
consensus validation are unchanged. The follow-up signed-index guard rebuilt the
same binaries and passed the focused main, coins, and database-wrapper groups.

The paired undo allocator now rejects negative or out-of-range file indices
before indexing `vinfoBlockFile`, and bounds size growth so both the 32-bit undo
size and its one-MiB chunk rounding remain representable. These checks also run
before position, size, or dirty-index mutation. `FindUndoPos()` measures McCabe
complexity 6, one required branch above its prior score; the validation helper
measures 5. Focused main, coins, and database-wrapper tests passed after the
change. The complete Boost suite passed all 386 cases and 142,483,793
assertions. Undo serialization and validation semantics are unchanged.

## Pruned reindex filename filtering (2026-09-20)

`CleanupBlockRevFiles()` previously classified files by length, a three-byte
prefix, and `.dat` suffix alone. During `-reindex -prune`, an unrelated name such
as `revision.dat` therefore matched the `rev?????.dat` shape and was deleted.
Block and undo cleanup now requires exactly five decimal digits between the
prefix and suffix before a path is considered.

The exact-name predicate is a pure utility with focused cases for valid block
and undo names, nondigits, wrong prefixes, unrelated names, and extra suffixes.
`CleanupBlockRevFiles()` decreases from McCabe complexity 8 to 6; the predicate
measures 5. All 24 utility cases passed (291 assertions), the three main tests
passed, and Valgrind reported zero errors and no definite, indirect, or possible
leaks for the predicate regression. The daemon and test binary rebuilt with the
normal warning set, and `git diff --check` passed.

This narrows destructive local cleanup only. Reindex parsing, block validation,
and consensus behavior are unchanged.
