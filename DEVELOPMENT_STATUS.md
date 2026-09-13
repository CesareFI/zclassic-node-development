# Zclassic development status

Updated: 2026-09-13 17:30 UTC. Read before starting a new task.

## Objective and constraints

Improve synchronization, peer handling, resource efficiency, memory/thread
correctness, code quality, tests, and build reliability using local code and
fixtures. Preserve consensus, monetary policy, PoW, transaction validity, and
upgrades. No external host interaction, mining, marketplace, pushes, production
changes, Goal mode, or sub-agents.

## Branch and latest validated work

- Branch: `fix/og-node-sync-20260913`.
- Latest committed unit: `d2afd7586`, test-daemon failure reporting and graceful
  cleanup. The bounded peer database loader described below is tested and ready
  to commit with this status file; use `git log -1` for its resulting hash.
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
- Normal and ASan actual-daemon smoke PASS: six peer teardowns each, height129,
  global counters zero, normal stop. `mission/addrdb-wire-{normal,asan}`.
- Both restart checks loaded the test-created peers.dat and retained height129;
  normal/ASan graceful stops 1.068/0.919s. No sanitizer findings.
- Initial build macro naming error was corrected. Initial restart check could
  not bind loopback under the sandbox, exited safely, then passed using the
  approved bounded script. Failed evidence retained in normal/restart.log.
- All new build and test jobs completed. Do not duplicate running work.
- Existing production monitor 51744 predates local-only scope; no new production
  actions or third-party probes were performed.

## Important limit

Captured historical block478544 passed strict historical validation, but current
code rejects its125,811-byte transaction as bad-txns-oversize after an ungated
historical size-limit change. No consensus bypass or rule change was made.
Production advancement is not claimed. Continue local engineering tasks.

## Next five tasks

1. Commit the validated bounded peer-file loader and regression cases.
2. Inspect address-manager deserialization bounds using local malformed fixtures.
3. Reproduce any identified accounting/state inconsistency before fixing it.
4. Run targeted normal/sanitizer checks for the next logical change and commit it.
5. Continue measured local resource/build/complexity improvements; perf is
   unavailable and external downloads are out of scope.

Resume: `cd /opt/zclassic-money && cat DEVELOPMENT_STATUS.md`.
