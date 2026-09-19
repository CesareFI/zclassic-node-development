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
