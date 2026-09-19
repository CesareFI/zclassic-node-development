# Storage reliability

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
