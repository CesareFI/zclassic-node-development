# Zclassic development status

Updated: 2026-09-13 15:20 UTC. Read before starting a new task.

## Objective and constraints

Improve synchronization, peer handling, resource efficiency, memory correctness,
code quality, tests, and build reliability using local code and local fixtures.
Preserve consensus, monetary policy, PoW, transaction validity, and upgrades.
No external host interaction, mining, marketplace, pushes, or production changes.
Continue as a normal Codex session: no Goal mode and no sub-agents.

## Branch and latest validated commit

- Branch: `fix/og-node-sync-20260913`.
- Latest tested commit: `2e3263f63` — saturated peer eviction regression.
- `f5f95715f` fixed HTTP buffered-event socket ownership.
- `3608da448` synchronized peer sockets, metadata, I/O statistics, and ping state.
- Earlier tested commits include `2bd9d05cc` (protocol-error teardown),
  `537ec5cb5` (getinfo lock), and `20937a8b3` (completed download benchmarks).
- Normal candidate: `src/zclassicd-mission`; build with
  `make -C src -j2 EXEEXT=-mission zclassicd-mission`.
- ASan/UBSan worktree: `mission/asan-source`; TSAN: `mission/tsan-source`.
  These contain current source copies; inspect parity before further builds.
- Service executable `src/zclassicd` remains unchanged, SHA256
  `bc161f5339039ca1bacd1653dd45c2b42f409c4982b029609e8316869cca3c4f`.

## Completed work

- Original in-flight leak reproduced and fixed: shared immediate/idempotent
  request cleanup, bounded configuration, operator download diagnostics.
- Completed all 16/32/64/128 healthy, stalled, and window benchmarks. Retained
  128 from measured throughput, recovery, request waste, and memory results.
- Networking concurrency commit passed 38 normal and ASan/UBSan unit cases,
  100 TSAN teardown cycles, 100 ASan/UBSan cycles, and pending-peer shutdown.
- Latest real outbound ASan/UBSan recovery passed: A disconnected after
  300.107 seconds despite 11 header messages; B validated through 129 without
  restart; normal shutdown and leak checks passed.
- Full evidence summary: `doc/og-node-sync-investigation.md`; private logs and
  earlier continuation history: `mission/CONTINUATION.md` and test directories.

## Current task: HTTP descriptor lifetime

ThreadSanitizer intermittently reported epoll descriptor access racing a
LevelDB directory close during startup. This is separate from the peer races.
A minimal local libevent HTTP/directory-read program reproduces it without
Zclassic or LevelDB code. Instrumenting the cached libevent source revealed:

1. evhttp_connection_free closes the socket in its write callback.
2. That callback still holds a buffered-event reference.
3. Returning from the callback drops the reference and removes epoll events.
4. Another thread may reuse/close that descriptor between steps 1 and 3.

The candidate uses BEV_OPT_CLOSE_ON_FREE so the buffered event closes its own
socket after its final reference removes the event registrations. It uses the
existing libevent API and backend, with no dependency patch or suppression.
CreateHTTPServer centralizes this policy and is used by InitHTTPServer and tests.

HTTP work committed as `f5f95715f`. Commit `2e3263f63` adds `--eviction`
coverage to `qa/rpc-tests/og-peer-teardown.py`, saturating 16 inbound slots and
checking one replacement per new peer while all 129 fixture blocks stay
assigned exactly once. Initial normal run `92826` failed from a fixture capacity assumption: Zclassic
reserves 16 outbound slots, so maxconnections=24 supplied only 8 inbound slots.
It exited normally; evidence is `mission/wire-eviction-normal`. Corrected run
`13110` with maxconnections=32 PASS: 24 replacements. TSAN `67009` and
ASan/UBSan `89026` PASS 64 replacements each. All keep 129 unique assignments,
recover to height 129, and stop normally without sanitizer findings. Observed
evicted requests reassigned: normal 128, TSAN 385, ASan 2. All jobs complete. Original malformed-path smoke `17256` also PASS: 10
cycles, 250 RPC calls, height 129 and normal exit, covering the extracted runner. No new C++ changes.

## Validation and active jobs

- Deterministic lifetime test FAILED before the fix: socket already closed
  while a buffered-event reference remained. Exactly one intended assertion,
  exit 201: `mission/http-lifetime-before.log`.
- The same test PASSED after the fix, including final descriptor release.
  Added keep-alive reuse/explicit-close test also PASSED.
- Normal relevant suites passed 39 cases in 55.141s before the added keep-alive
  case; both HTTP cases then passed (`mission/http-unit-keepalive*`).
- Actual-daemon TSAN integration `18677` PASS: 100 teardown cycles, 2,465 RPC
  calls, height 129, no warnings, normal shutdown in 0.618s.
- Actual-daemon ASan/UBSan integration `56673` PASS: 50 teardown cycles, 1,000
  RPC calls, normal shutdown with 128 pending requests in 0.818s; leak checks on.
- ASan/UBSan unit run `38361` PASS: all 40 relevant cases in 73.083s, logs
  `mission/http-asan-unit.log` and `mission/http-asan-unit-report.log`.
- All build jobs and other test jobs completed. Do not duplicate running work.
- Original failing TSAN evidence remains under `wire-pending-stop-tsan`,
  `wire-malformed-tsan-handshake-lock`, and `tsan-http-fd-reuse*.log` in mission.
- Existing read-only production monitor `51744` predates the latest local-only
  scope. No new production actions or third-party probes are authorized.

## Important limit

Captured historical block 478544 passed strict historical validation, but current
code rejects its 125,811-byte transaction as bad-txns-oversize after an ungated
historical size-limit change. No consensus bypass or rule change was made.
Production advancement is not claimed. Continue local engineering tasks.

## Next five tasks

1. Commit lifecycle reporting: unit checks and real pending-peer smoke `80748`
   passed. Real stop-RPC fault injection `93083` retained failure, sent SIGTERM,
   and exited normally with 128 pending requests in 0.277s.
   Uncommitted: extracted shutdown helpers and `test_og_peer_teardown.py`.
2. Inspect the next bounded local profiling or resource-efficiency task.
   perf is unavailable locally; do not install/download external tooling.
3. Profile local eviction selection before considering allocation/hash caching.
4. Improve test failure reporting so already-exited daemons retain their exit
   status without a pointless RPC shutdown attempt.
5. Continue bounded local resource, build, and code-quality improvements with
   tested logical commits and regular status updates.

Resume: `cd /opt/zclassic-money && cat DEVELOPMENT_STATUS.md`.

Lifecycle before/after evidence: `mission/lifecycle-{before,after}-early-exit`.
Both intentionally failed startup using /bin/false; before lost exit status and
reported an unrelated missing-cookie shutdown error. After records exit 1 and
stop_attempted=false. Real child tests cover early exit 0/7, successful RPC stop,
RPC failure, and shutdown timeout. Fallback never sends SIGKILL and does not
convert an RPC failure or timeout into a passing result.
