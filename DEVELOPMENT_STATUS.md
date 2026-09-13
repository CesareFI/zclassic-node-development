# Zclassic development status

Updated: 2026-09-13 21:47 UTC. Read before starting a new task.

## Objective and constraints

Improve synchronization, peer handling, resource efficiency, memory/thread
correctness, code quality, tests, and build reliability using local code and
fixtures. Preserve consensus, monetary policy, PoW, transaction validity, and
upgrades. No external host interaction, mining, marketplace, pushes, production
changes, or sub-agents. The current user requests continuous autonomous work.

## Branch and latest validated work

- Branch: `fix/og-node-sync-20260913`.
- Latest committed unit: `dc4beef1d`, malformed address-manager parser recovery.
- Preferred header-discovery milestone validated and ready to commit (see git log).
- `c214ec7de`: complete address-manager cleanup.
- `9b3d73993`: bounded peer database loader.
- `d2afd7586`: test-daemon failure reporting and graceful cleanup.
- `2e3263f63`: saturated peer eviction coverage.
- `f5f95715f`: HTTP buffered-event socket ownership.
- `3608da448`: synchronized peer sockets, metadata, I/O statistics, and ping state.
- Earlier: `2bd9d05cc` protocol-error teardown, `537ec5cb5` getinfo lock,
  `20937a8b3` completed download benchmarks.
- Normal candidate: `src/zclassicd-mission`; build with
  `make -C src -j2 EXEEXT=-mission zclassicd-mission`.
- ASan/UBSan worktree: `mission/asan-source`; TSAN: `mission/tsan-source`.
  Loader source matches both copies; normal/ASan daemon and units are rebuilt.
  TSAN daemon has the prior HTTP fix and has not been rebuilt for the loader.
- Service executable `src/zclassicd` remains unchanged, SHA256
  `bc161f5339039ca1bacd1653dd45c2b42f409c4982b029609e8316869cca3c4f`.

## Completed work and evidence

Original in-flight accounting leak reproduced and fixed using shared immediate,
idempotent request cleanup. All 16/32/64/128 healthy, stalled, and window
benchmarks completed; retained 128 using measured throughput/recovery/RSS and
request waste. No need to repeat these completed benchmarks.

Networking changes passed unit, real-socket, ASan/UBSan/leak, and TSAN checks.
An outbound stalled peer timed out in 300.107 seconds despite 11 header messages;
healthy B validated through 129 without restart. HTTP lifetime regression failed
before the socket-ownership fix and passed after; full instrumented libevent
confirmed descriptor reuse after early evhttp close. Real daemon TSAN passed
100 teardown cycles, 2,465 RPC calls, height 129, and normal shutdown. Saturated
peer eviction passed 64 cycles each under ASan and TSAN with 129 unique requests.
Lifecycle tests preserve premature daemon exits and stop-RPC errors; a real
injected stop failure gracefully terminated only the owned test daemon with
128 requests pending (0.277s), retaining the failed test result.

Detailed investigation: `doc/og-node-sync-investigation.md`. Private evidence,
builds, and older history: `mission/` and `mission/CONTINUATION.md`.

## Bounded peer database loader: validated

CAddrDB::Read narrowed file_size to int, indexed an empty vector for short files,
and duplicated the payload buffer. Reproduced before changing the loader:

- A valid tiny peers.dat extended by 2^32 sparse bytes was accepted after integer
  wrap. Intended assertion failed, exit 201: `mission/addrdb-wrap-before*`.
- Short-file read triggered UBSan null-reference diagnostics at the empty vector
  access: `mission/addrdb-before-ubsan-excerpt.txt`, `addrdb-short-asan-before*`.

The fix measures the opened file with fseek/ftell, checks the existing 32 MiB
serialization bound before allocation, and reads directly into CDataStream.
Canonical current address tables fit below 5.1 MiB (62-byte records, table
counts and indices, key/header/checksum). No consensus code changed.

- Six new addrdb cases: valid roundtrip, short/missing/directory paths, checksum
  corruption, sparse size wrap, oversized sparse file. Owned temporary dirs only.
- Normal relevant suites PASS: 57 cases, 48.136s. ASan/UBSan/leak suites PASS:
  57 cases, 77.791s. Logs `mission/addrdb-{unit,asan}-after*`.
- Oversized-file workload RSS: 91,216 to 27,192 KiB; time 0.19 to 0.06 seconds.
  This is a malformed-file microbenchmark, not a whole-node RAM claim.
- Normal and ASan actual-daemon smoke PASS: six peer teardowns each, height 129,
  global counters zero, normal stop. `mission/addrdb-wire-{normal,asan}`.
- Both restart checks loaded the test-created peers.dat and retained height 129;
  normal/ASan graceful stops 1.068/0.919s. No sanitizer findings.
- Initial build macro naming error was corrected. Initial restart check could
  not bind loopback under the sandbox, exited safely, then passed using the
  approved bounded script. Failed evidence retained in normal/restart.log.
- All new build and test jobs completed. Do not duplicate running work.
- Existing production monitor 51744 predates local-only scope; no new production
  actions or third-party probes were performed.

## Important limit

Captured historical block 478544 passed strict historical validation, but current
code rejects its 125,811-byte transaction as bad-txns-oversize after an ungated
historical size-limit change. No consensus bypass or rule change was made.
Production advancement is not claimed. Continue local engineering tasks.

## Next five tasks

1. Finish address-selection sparse-table and recent-failure regressions.
2. Complete ASan build and rerun make for the latest test-file edits.
3. Validate bounded address selection normally and under sanitizers.
4. Run isolated daemon restart/teardown checks for address selection; commit.
5. Review remaining header-only stalls and address-manager locking with tests.

Resume: `cd /opt/zclassic-money && cat DEVELOPMENT_STATUS.md`.

## Active address-manager review

CAddrMan::Clear resets buckets, counts and the selection vector but leaves
mapInfo/mapAddr populated. Deserializing into an existing manager can therefore
leave a stale address lookup pointing at a replacement ID. Both new regression cases FAILED before the fix (exactly two stale-lookup
assertions, exit 201); mission/addrman-clear-before-suites*. The first attempted
combined Boost case filter matched no tests (exit 200); reran the whole addrman
suite to obtain the intended baseline. Candidate Clear now clears both maps
and holds the existing recursive address-manager mutex while resetting state.
This tested logical cleanup unit is ready to commit; git log -1 gives its hash.
Next inspect signed deserialization counts and failure-state recovery.

Normal addrman cleanup build 43086 and ASan/UBSan build 68285 PASS. Targeted
addrman/addrdb suites 54889 and sanitizer/leak run 40577 PASS (19 cases each).
Logs: mission/addrman-clear-after* and addrman-clear-asan-after*. All jobs done. No new daemon test is running. This header is widely
included, so rebuilds are larger than the previous loader-only change.

Follow-up review findings (not changed or yet claimed reproduced):
- nNew/nTried are deserialized into live signed counters; only upper bounds are
  checked. Negative values can survive successful parsing.
- nUBuckets and per-bucket nSize have no lower-bound checks.
- Unserialize clears first, then mutates live state. A truncated input can leave
  partial maps/counters after CAddrDB catches the exception and continues startup.
- size() reads vRandom without cs; Add logs nNew/nTried after releasing cs.
These are local engineering candidates. Preserve old supported addrman versions
and table reconstruction when designing malformed-file rejection tests.

Added four local regression cases before changing the parser: negative header
counts (versions0/1/2, -1/INT_MIN), negative bucket sizes, truncation after one
complete entry, and save/load after rejecting an oversized header. No peer
network or production activity is required. Clear cleanup is committed c214ec7de.

Malformed-parser baseline FAILED with exactly 26 assertions (exit201):
24 negative-count acceptance cases, retained partial entry, and save/load
failure after rejected header. Evidence mission/addrman-malformed-before*.
Candidate separates header, entry and bucket-position parsing; rejects negative
counts, clears all partial state on any decoding exception, and rethrows it.
No supported version, positive bucket count or reconstruction policy changed.
Added compatibility coverage plus deterministic truncation at every byte of
a valid serialized one-address table. Rebuilding normal and ASan suites next.


## Resumed verification, 21:38 UTC

Live process 503646 still runs deleted executable inode SHA256
6c4a80ec792c894aa1be9d27332f7d05e857e36408485e3b651fe114f3be14ad,
matching the deployment evidence for e9fa74638. The on-disk src/zclassicd
SHA remains bc161f53...; neither is the current candidate source. No production
RPC, service action, or datadir change was performed. Disk has 19 GiB free.

Address-manager malformed parser passes all 25 addrman/addrdb cases under normal
and ASan/UBSan/leak builds (exit zero). Logs: mission/addrman-parser-{after,
asan-after}-20260913T2136.log. Original 26-assertion parser failure evidence is
preserved. Version 0/1/2 reconstruction and all truncated prefixes covered.
Initial resumed runs were terminated after revealing unrelated random Select()
empty returns and long sleeps; parser tests now assert decoded address lookups
and exact records instead of relying on probabilistic selection. No production
selection code has yet changed. Source candidate fixes negative counts and
clears partial deserialization state, with no consensus or wire-format changes.

New preferred-header test hypothesis: while inbound A has fSyncStarted and 128
requests, outbound B is preferred but receives no getheaders because nSyncStarted
is nonzero. Existing tests inject headers into both peers, masking this case.
Two new regression cases are building; production scheduling source unchanged.


## Preferred header discovery validated, 21:47 UTC

Two unit cases failed before the fix (exit201, missing getheaders), and the real
normal daemon failed because quiet preferred B never received requests (normal
shutdown, no peer errors). After the bounded preferred header-sync fix, all40
selected normal cases PASS52.638s and ASan/UBSan/leak PASS79.482s. Both real daemon
mixed-direction recovery runs PASS: eight inbound reconnect cycles each, A
holds128 blocks, B only advertises headers when asked, timeout300.037/300.068s
despite11 header messages, B validates129, globals0, normal stop0. Evidence:
mission/preferred-headers-{before,unit-after,asan-after}.log and wire-{before,
after,asan}/ under the same prefix. Production untouched, no consensus edits.

Address-selection follow-up is UNCOMMITTED: one usable new address produced six
empty selections in128 deterministic attempts (mission/addrman-sparse-before.log,
exit201). Existing code sleeps100ms per1000 probes with cs held, up to20s per
failed search. Candidate factors the duplicated search, caps random probing,
and falls back to uniform reservoir sampling of occupied bucket slots; removes
sleeps and preserves table choice, reference weighting, and chance penalties.
First normal run passes the new regression but fails four legacy exact-random-
sequence assertions. Those now test membership/coverage across both tables and
all ports; revised26-case suite passes in0.66s. Recent-failure checks were added
subsequently and need a fresh build/run. ASan build session26755 is still running;
latest test source must be copied/rebuilt after it completes. Normal/ASan wire
header runs have completed and both owned daemons stopped. No production action.
