# Peer-address state reliability

## Reset and cache-load recovery (2026-09-19)

`CAddrMan::Clear()` reset its bucket arrays, random-selection vector, key, and
counters, but left both address lookup maps populated. A local regression
confirmed that cleared addresses remained discoverable and could not be added
again. Clearing both maps restores the intended empty-state invariant and
releases their entries.

`CAddrDB::Read()` also retained partially loaded state when address
deserialization failed. An isolated fixture with a valid checksum, one address,
and missing bucket data returned failure while leaving that address in memory.
The exception handler now clears the incomplete state before returning failure,
allowing ordinary peer discovery to rebuild the cache.

The two regressions cover new and tried entries, clearing and re-adding an
address, peer selection, serialization round trips, and recovery after a failed
cache parse. Files are confined to the existing `TestingSetup` temporary
directory. Both tests failed before the fix and passed afterward (22
assertions). The final fixtures use the existing deterministic address-manager
test support to avoid random selection delays.

Validation:

- Rebuilt `zclassicd` and `test/test_bitcoin` using the recorded native build
  configuration in `ibd-performance.md`.
- 112 relevant Boost tests passed, with 46,274,641 assertions, covering address
  management, networking, DoS handling, bootstrap protocols, validation,
  serialization, and database wrappers. After making the two fixtures
  deterministic, their focused tests passed again.
- Valgrind checked the final two regressions: zero errors and no definite,
  indirect, or possible leaks. Approximately 71.7 MB remained reachable at
  process exit; this is not a claim of a completely freed process heap.
- The loopback reconnect/reassignment regression passed three request cycles,
  with approximately 300-second deadlines in each cycle, then validated the
  expected 100-block tip
  `00001071e9da677300cf65b92f954b00184f941e6b51e9e6d5927be0ac277271`.
- Compiler warnings and the exact diff were reviewed; `git diff --check` passed.

The change affects peer-cache cleanup only. Address serialization and scheduling
policy are unchanged, as are chain history, all consensus parameters, block and
transaction validity, and cryptographic validation. No production datadir or
wallet was used, and generated files are excluded from the commit.

## Cache file size bounds (2026-09-19)

`CAddrDB::Read()` previously narrowed the filesystem's unsigned file size to
`int`, allocated the resulting payload before applying any upper bound, and
formed `&vchData[0]` even when the payload vector was empty. A local sparse-file
fixture one byte above the 32 MiB serialization limit was fully allocated and
hashed before rejection. A checksum-only fixture exercised the empty-payload
path.

The extracted file reader now validates the full file size before allocation.
A cache must contain at least the four-byte network magic plus its 32-byte
checksum, and its payload may not exceed the existing `MAX_SIZE` serialization
bound. Only then is the checked `uintmax_t` length converted to `size_t` and read
through `vector::data()`. Filesystem exceptions, allocation failures, and read
errors remain handled by the existing `CAddrDB::Read()` exception boundary.
Its measured McCabe complexity decreased from 5 to 4; the helper measures 3.

The focused fixture passed before and after because both versions eventually
reject malformed files, but peak RSS fell from about 148 MB to 83 MB and wall
time fell from 1.55 to 1.31 seconds. Test-process startup and parameter loading
dominate those times. The test uses a sparse temporary file under
`TestingSetup`; no production cache is read or retained.

All 28 addrman, netbase, and database-wrapper cases passed (3,348 assertions).
Valgrind reported zero errors and no definite, indirect, or possible leaks for
the focused bounds fixture. The daemon and Boost test executable rebuilt with
the normal warning set, with no warning at a changed line. A full GCC analyzer
run over the large `net.cpp` translation unit was stopped after two minutes at
roughly 14 GB RSS; it had emitted only existing conversion and `tinyformat.h`
warnings and had not produced a finding. `git diff --check` passed.

This is local peer-cache parsing only. The serialized cache format and all
network and consensus behavior remain unchanged.

## Temporary-file cleanup (2026-09-19)

`CAddrDB::Write()` writes a randomly named `peers.dat.XXXX` file, closes it,
and renames it over the final cache. When the rename failed, the temporary file
was left in the datadir. Repeated failures could accumulate stale cache files;
an exception during serialization had the same cleanup gap.

A local regression makes the final `peers.dat` path a directory so the rename
fails without fault injection. Before the fix, one temporary file remained.
The write path now owns every successfully opened temporary path through a
noncopyable scoped remover. Declaration order closes the `CAutoFile` before
cleanup, which also works on platforms that cannot unlink an open file. A
successful rename immediately dismisses cleanup, preventing a later file with
the same name from being removed. `CAddrDB::Write()` remains at McCabe
complexity 3.

The final tree rebuilt `zclassicd` and `test/test_bitcoin`. Three focused cache
recovery, bounds, and write-cleanup tests passed (19 assertions), followed by 48
addrman, netbase, database-wrapper, and utility cases (3,618 assertions).
Valgrind reported zero errors and no definite, indirect, or possible leaks in
the forced rename-failure case. The normal warning review and
`git diff --check` passed.

This changes failure cleanup only. Successful cache bytes and rename behavior,
peer selection, networking, and consensus validation remain unchanged.

## Durable cache commit checks (2026-09-19)

`FileCommit()` previously discarded errors from `fflush()` and the platform
durability operation. Consequently, `CAddrDB::Write()` could rename a temporary
peer cache into place after either operation failed. `FileCommit()` now reports
success, and the address database treats a failed commit like its other
serialization and I/O failures. The existing scoped remover deletes the
temporary file after the stream closes, while the prior `peers.dat` remains in
place.

The commit check is isolated in a small helper so `CAddrDB::Write()` retains its
McCabe complexity of 3; the helper measures 2. Other callers retain their
existing behavior until their failure handling can be audited separately. A
focused utility regression verifies the successful write, flush, and durability
path without using a production datadir.

The daemon and Boost test executable rebuilt successfully. Three focused tests
passed (18 assertions), covering the commit path, failed-write cleanup, and
corrupt-cache recovery. All 49 utility, addrman, netbase, and database-wrapper
cases then passed (3,622 assertions). Valgrind reported zero errors and no
definite, indirect, or possible leaks for the commit regression. A bounded GCC
analyzer run over the legacy `util.cpp` translation unit was stopped after its
RSS grew to approximately 7.6 GB without a project finding; the normal warning
build completed without a warning at a changed line. `git diff --check` passed.

This changes local peer-cache crash handling only. Peer-cache serialization,
network behavior, and all consensus rules and validation remain unchanged.
