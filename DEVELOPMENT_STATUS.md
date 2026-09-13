# Zclassic development status

Updated: 2026-09-13 14:40 UTC. Read this file before starting another task.

## Objective and constraints

Improve synchronization, peer handling, memory correctness, resource use, code
quality, tests, and build reliability using local repository code and fixtures.
Preserve consensus, monetary policy, PoW, transaction validity, and upgrades.
No external host interaction, marketplace functionality, mining, or pushes.
Continue as a normal Codex session, without Goal mode or sub-agents.

## Branch and worktrees

- Branch: `fix/og-node-sync-20260913`.
- Latest tested commit: `2bd9d05cc` — protocol-error socket teardown regression.
- Earlier commits: `537ec5cb5` (`getinfo` connection-count lock), `8c1892bc7`
  (concurrent RPC/socket teardown), `20937a8b3` (completed download benchmarks).
- ThreadSanitizer worktree: `mission/tsan-source`, based on `537ec5cb5` plus
  current uncommitted networking changes.
- ASan/UBSan worktree: `mission/asan-source`; current source copied there,
  but its daemon has not yet been rebuilt for the new race fixes.
- Normal test candidate: `src/zclassicd-mission`, built with
  `make -C src -j2 EXEEXT=-mission zclassicd-mission`. This preserves the
  service executable `src/zclassicd` while candidate changes are tested.

## Completed work and evidence

- Fixed leaked validated in-flight accounting and premature/late peer cleanup.
  The deterministic regression failed before the fix and passed afterward.
- Added bounded per-peer request configuration and download diagnostics.
- Completed healthy, stalled-peer, and download-window benchmarks for
  16/32/64/128 requests. Retained default 128 based on measured throughput,
  recovery, request waste, and small memory differences.
- Normal and ASan/UBSan relevant unit suites: 37 cases passed, most recently
  42.273/71.897 seconds for the `getinfo` lock fix.
- Real outbound recovery: stalled peer disconnected after 300.115 seconds
  despite continued headers; healthy peer reached fixture height 129 without
  restart; ASan/UBSan/leak checks and normal shutdown passed.
- Real teardown tests cover FIN, reset, RPC disconnect, invalid network magic,
  and oversized frame declarations in both connection directions. Latest
  pre-race-fix malformed runs: 50 normal and 100 ASan/UBSan cycles passed,
  with normal validation to height 129 and zero outstanding accounting.
- Detailed evidence: `doc/og-node-sync-investigation.md`; private raw logs,
  fixtures, and earlier continuation notes remain under `mission/`.

## Validated networking changes ready for commit

Files: `src/net.h`, `src/net.cpp`, `src/main.cpp`, `src/rpc/net.cpp`,
`src/test/block_download_tests.cpp`, and the teardown harness.
Validation is complete for this logical unit. The harness now has a tested
`--shutdown-pending` mode and extracted final-peer/cleanup helpers to test
shutdown while 128 requests remain assigned.

1. Atomic peer send/receive timestamps and byte counters. ThreadSanitizer proved
   `nLastRecv` and `nRecvBytes` races between network writes and RPC snapshots.
2. Private socket handle with a dedicated mutex. Snapshot reads serve select
   bookkeeping; send/receive syscalls and close share the mutex. It is released
   before acquiring receive-buffer locks. ThreadSanitizer proved a handle read
   racing message-thread close. Shutdown relies on CNode destruction to close
   peer descriptors after network threads stop.
3. `cs_main` protects version-handshake metadata and preferred-download state.
   Protocol version is atomic for socket timeout/eviction readers. Parsing order
   and rejection conditions are preserved. ThreadSanitizer proved a subversion
   string read/write race; source review found the same handler updated download
   roles without their required lock.

4. Ping state now has one mutex across sending, pong handling, RPC requests,
   snapshots, and timeout checks. `MaybeSendPing` reduces SendMessages complexity
   and releases that mutex before sending. Eviction sorts captured ping values.
   The new wire-nonce unit case and `--rpc-pings` stress option both passed.

## Test failures and current jobs

- `mission/wire-malformed-teardown-tsan`: first timestamp race, test failed.
- `mission/wire-malformed-tsan-baseline-all`: 50 cycles recovered, but two races
  were reported and daemon exited 66. This is a failed sanitizer result.
- `mission/wire-malformed-tsan-io-atomics`: socket-handle race after 23 cycles.
- `mission/wire-malformed-tsan-socket-lock`: subversion string race after about
  70 cycles. These reports were preserved; no suppressions were added.
- Latest TSAN build session `91136` completed successfully, including the
  handshake fix. Runtime regression `46686` failed during startup: a descriptor-lifetime
  report between libevent epoll handling and LevelDB closedir prevented peer
  coverage. Report retained in `mission/wire-malformed-tsan-handshake-lock`.
  Collect-all run `93492` completed 100 cycles and recovery, but exited 66
  for a ping nonce/timestamp race (SendMessages versus RPC statistics).
  The earlier receive-stat, handle, and handshake races were not reported.
  A minimal unrelated-descriptor reuse check passed; the startup libevent
  report remains unresolved and is not suppressed.
- Ping-state build `49515` failed because two LOCK macros shared a scope.
  Changed the constructor to LOCK2; replacement TSAN build `18022` completed successfully.
  100-cycle TSAN run `13392` PASS: `mission/wire-malformed-tsan-ping-lock`,
  1,715 concurrent RPC calls including ping; height 129, zero accounting,
  normal exit 0 in 0.373 seconds, no TSAN warnings. Maximum release 0.176s.
  Normal unit build `5335`, units `64506` (38 cases PASS), and candidate build
  `92302` completed successfully. Normal 50-cycle stress `33637` PASS: height 129, 575 RPC calls, stop 0. ASan daemon build `27997` completed. ASan malformed stress `25711` PASS: 100 cycles, 1,295 RPC calls, height
  129 and normal shutdown; unit build `16569` completed; outbound recovery
  `39541` PASS: 300.107-second timeout despite 11 header messages, height 129,
  no restart and normal shutdown. ASan units `12839` PASS all 38 cases in
  73.254 seconds; ASan pending shutdown `86050` PASS with 128 requests in
  0.823 seconds. No heavy build or test jobs remain running. TSAN pending-peer
  shutdown test `12320` failed during startup on the separate libevent/LevelDB
  descriptor report, before any peer round. Collect-all run `89056` PASS: 10 cycles, 135 RPC calls, normal exit 0
  with 128 pending requests in 0.323 seconds; no TSAN warnings.
- The separate startup descriptor report now reproduces in a minimal local
  libevent HTTP + directory-read program without any node or LevelDB code:
  `mission/tsan-http-fd-reuse.cpp`, failing log of the same name. Full dependency instrumentation identified HTTP connection free closing the
  socket before the write callback drops its buffered-event reference and
  deletes epoll registrations. A local API-level experiment using
  BEV_OPT_CLOSE_ON_FREE passed 2,000 requests with no TSAN warning; the default
  failed. No node HTTP code, suppressions or backend changes applied yet.
- All earlier benchmark, normal-test, ASan-test, and candidate-build jobs have
  completed. Do not duplicate jobs; inspect live sessions before resuming.
- Existing read-only production monitor session `51744` predates the latest
  local-fixture-only scope. No further production changes or external probes.

## Important limits

The historical active-node sync blocker is separate: captured block 478544 is
on the established chain and passed strict historical validation, but current
code rejects its 125,811-byte transaction as `bad-txns-oversize` after an
ungated historical size-limit change. No consensus bypass or rule change was
made. Production advancement is not claimed. Continue local engineering tasks.

## Next five tasks

1. Commit the fully validated networking race fixes, ping unit test, teardown
   harness extensions, evidence summary, and this continuation file.
2. Apply and validate buffered-event socket ownership in the local HTTP server;
   keep this separate from the peer-state commit and preserve failing evidence.
3. Add a deterministic local dependency regression for HTTP callback teardown,
   then run normal, ASan/UBSan, and TSAN startup/request/shutdown coverage.
4. Exercise saturated local peer eviction to cover stable ping snapshots and
   audit remaining peer lifetime/lock boundaries.
5. Continue the local reliability/resource/code-quality backlog with bounded
   tests and tested logical commits; update this file before switching tasks.

Resume: `cd /opt/zclassic-money && cat DEVELOPMENT_STATUS.md`.
