# Zclassic development status

Updated: 2026-09-14 06:35 UTC.

## Current mission

Continue autonomous original-node reliability, synchronization, diagnostics,
efficiency, and defensive correctness work. Preserve consensus and /root/.zclassic.
No main push, production changes, destructive data operations, mining, external
peer scanning, or malformed-message/socket-security campaigns. Do not resume the
unfinished sequence described below. If a tool refuses any security operation,
abandon that operation immediately and move to another safe task; no retry or
reformulation. Current user instruction was read from
/root/.codex/attachments/678d6916-f1aa-4a5e-8b29-7baea7b4168c/pasted-text-1.txt.

## Repository and production

- Working directory /opt/zclassic-money, branch fix/og-node-sync-20260913.
- Latest committed milestone bb281eb0d: scheduler-observed import pauses.
- Prior 6271d5701: HTTP resource budget validation.
- Prior 61231d83b: HTTP worker handle ownership.
- Prior 7c9c6bdc1: HTTP work-queue interruption.
- Prior e891a2958: script-thread budget conversion.
- Prior c943c90f1: first-run pruning defaults.
- Prior 4dcfff81b: configuration read/error handling.
- Prior 5631a27da: pruning budget validation.
- Prior f5ef27a3c: seed queue permit ownership.
- Prior a3e91ee5d: scheduler deadline ownership.
- Prior 8a11ae4eb: VerifyDB reconnect cancellation.
- Prior c32d3ba5d: join workers after startup failure.
- Prior 2e921face: PID-file ownership.
- Prior 01a79bb9e: completed-startup shutdown path.
- Prior a0f62634d: connection-budget conversion.
- Prior 073d1e5be: cache-budget conversion.
- Prior e614b767b: bounded preferred-source scan.
- Prior 0514633fa: inbound fallback after completed preferred discovery.
- Prior 865993abf: header-response deadlines; 286036078: header completion.
- Prior a7f7bd07d: peer download role diagnostics.
- Prior 60548418a: immediate owned-notfound response recovery.
- Prior milestones: 8edfb0afd address counts; 549a2f43a sparse selection;
  55cf564aa preferred outbound header discovery;dc4beef1d parser recovery.
- Running production PID 503646 uses deleted inode SHA256
  6c4a80ec792c894aa1be9d27332f7d05e857e36408485e3b651fe114f3be14ad
  (deployment e9fa74638). On-disk src/zclassicd remains SHA256
  bc161f5339039ca1bacd1653dd45c2b42f409c4982b029609e8316869cca3c4f.
  Neither matches current candidate source. No production action this continuation.
- Build normal candidates without replacing service executable:
  make -C src -j2 EXEEXT=-mission zclassicd-mission.
- Repository-local Git identity now Codex <codex@localhost>, per updated user rule.

## Preserved completed evidence

Existing accounting, timeout, peer lifetime, benchmark, parser and sanitizer
results remain valid for their stated versions/scopes. Do not repeat completed
security sequences. See doc/og-node-sync-investigation.md and private mission/.
Recent ordinary synchronization evidence: eight reconnects then inbound A with 128 requests,
quiet preferred B discovers headers, A timeout 300.037/300.068s, B validates 129 blocks
(normal/ASan), global requests 0, no restart. notfound variant: outbound A with 128 / B with 0 requests, valid
negative response, disconnect 0.704/0.657s, B validates 129 blocks, global requests 0, normal stops.
Notfound selected 43 normal cases PASS 49.375s, ASan/UBSan/leak PASS 87.799s.

Block 478544 has a separate historical transaction-size incompatibility. Existing
strict historical validation accepts it; current code rejects bad-txns-oversize
because of an ungated later size-limit reduction. No consensus changes or bypass
were made. Production advancement is not claimed. Preserve all historical evidence.

## Set-aside unfinished work

Misbehavior score locking/saturation and Bloom lock-order follow-up were unfinished
when the mission changed. Preserved reversibly in stash@{0}, message
"Preserve unfinished misbehavior work; pause sequence per updated mission".
Source files and all private evidence are intact. Do NOT pop/restart that sequence.
All its prior build/test processes had stopped before stashing. The TSAN
worktree still contains those candidate source copies; do not run that sequence.
The ASan source files were restored from the root working tree before building
the current diagnostic changes. Root source was restored to 60548418a before
starting this diagnostic milestone.
Detailed previous status preserved in mission/status-before-updated-mission-20260913T2244.md.

## Validated diagnostic milestone

Add per-peer header_sync_started and block_download_stopped fields to
getpeerinfo, using existing state under cs_main. Extend sync-status.py with
those roles and known heights. Identify downloaders using request counts even
when the known-height list is empty; prefer global counts from the same peer
snapshot rather than a preceding blockchain RPC call.

- New ordinary RPC regression failed before the C++ change (missing role field).
- Normal test passes: 687 assertions, 2.074 seconds. Covers fresh/assigned/stopped
  states, idempotent disconnect and healthy reassignment through fixture 129.
- Five local Python fixture tests pass; both omitted downloader and mismatched
  RPC snapshot counts failed before their respective fixes.
- Candidate daemon built as src/zclassicd-mission. Production untouched.
- ASan/UBSan/leak check passes: the same 687 assertions, 3.943 seconds.
  Its source files exactly matched the staged diagnostic snapshot.
- Evidence: mission/download-diagnostics-*.log.

## Validated header-completion milestone

Three ordinary regressions reproduced a retained header role after valid empty
or short responses. Completion now frees that role and remembers the initial
exchange ended, retaining preferred eligibility and outstanding block ownership.

- Eight selected ordinary cases pass: 5,162 assertions, normal 12.132 seconds,
  ASan/UBSan/leak 25.275 seconds. No excluded security sequence was run.
- New og-header-discovery.py: normal empty/short responses and instrumented short
  response all pass. A holds 128 / B receives block 129 in the short case;
  ordinary A disconnect releases work and B validates all 129. Exit 0, no errors.
- Existing valid-notfound wire recovery passes after two reconnects. Its fixture
  leaves A's getheaders unanswered to isolate negative-response role cleanup.
- Normal and ASan candidates both built as zclassicd-mission in their own trees.
- Evidence: mission/header-completion-*.

Next: investigate unanswered initial header requests with no outstanding blocks.
They currently have no response-specific timeout. Use ordinary state-machine
fixtures and mock time; preserve validation and avoid peer-name discrimination.
Do not resume the stashed sequence or repeat completed security campaigns.


## Validated header-response timeout milestone

Committed as 865993abf. All tests finished before the commit.

A 15-minute per-response deadline expires unanswered header exchanges even with
no block requests. It renews only when validated chain work advances in a full
160-header batch, supporting a shorter fork with more work. Empty/short completion
and disconnect clear it. Import/reindex cancels an active exchange for a fresh
retry after replies stop being ignored. No consensus/protocol changes.

- Initial silent-header baseline fails four assertions; repeated valid full batch
  baseline fails three. Advancing-batch control passes before/after.
- Final chain-work-based version: 12 ordinary cases, 8,063 assertions all pass
  normally (15.944 seconds) and ASan/UBSan/leak (32.477 seconds).
- Six Python tests pass, including deadline display; that test failed before.
- ASan timer source exactly matched the staged snapshot before building; its
  source tree has since been advanced to the next fallback task. Timer executable
  zclassicd-mission remained SHA256 e3c476353f08aac42d0c827ea6495cf0a1ec5c862bbecd4b298eb53315ac453a.
- Final normal short-response wire case passes. Early normal timer silent case
  passes after 900.107s; FINAL instrumented timer silent case passes after
  900.099s. Both validate 129, counters zero, exit 0, no peer/sanitizer errors.
- All timer build/unit/wire jobs completed. Do not duplicate completed runs.
- Evidence: mission/header-timeout-*. Header extension fixture is staged with
  checksum/provenance in src/test/data/README.md.

## Validated inbound fallback milestone

HasPreferredDownloadSource consults completed discovery and
validated available work instead of excluding inbounds merely because an outbound
remains connected. Pending preferred discovery, assigned work, and validated work
beyond the active tip retain priority. Known inventory is resolved before deciding.

- Ordinary baseline: outbound answers empty; inbound gets no getheaders. Exit 201.
- Three new cases plus 12 timer/recovery controls pass 9,955 assertions normally
  (19.640s) and under ASan/UBSan/leak (39.049s).
- Real baseline fails B discovery; fixed normal and instrumented daemons validate
  129, counters zero, exit 0, no peer or sanitizer errors. Outbound A stays connected.
- Initial wire attempts used maxconnections=8, below 16 reserved outbound slots;
  B was dropped before handshake. Those failures remain preserved. The isolated
  inbound fixture now uses 32. Corrected evidence: mission/inbound-fallback-wire-
  {before,after,asan}-capacity. Unit/build logs: mission/inbound-fallback-*.
- Normal and ASan next candidates are zclassicd-fallback, separately named from
  the completed timer binaries. No production executable/service/data changed.
- All fallback test/build processes completed. Do not resume the paused stash.


## Validated idle scheduling optimization

Stop checking peer state once the existing preferred count has been examined.
No additional mutable index or ownership state. Three quiet loop measurements
(1,000 full rounds; preferred peer first) improved median 125-peer time from
0.103885s to 0.023699s; 750-peer time from 2.528977s to 0.157800s. These are local
scheduling-loop measurements, not whole-node CPU estimates.

- Added bounded 125/750-peer completed-role coverage and a preferred source after
  64 inbound peers. Late preferred discovery/work retains priority, then cleanup
  allows inbound takeover and full fixture validation.
- 18 selected ordinary cases / 20,067 assertions pass normally (21.007s) and
  ASan/UBSan/leak (46.137s). Both zclassicd-mission candidates rebuild successfully.
- All builds/tests complete; evidence mission/scheduling-{idle,scale}-*.
- Initial benchmark constructor had an unsigned-overload ambiguity; corrected to
  the explicitly bounded int port before recording successful measurements.
- Next: isolate and test cache-size conversion. init.cpp currently shifts the
  signed -dbcache argument before clamping. Test pure arithmetic without startup
  or live datadir access, then fix conversion order if reproduced.


## Validated cache-budget conversion

Startup converted the signed -dbcache MiB value to bytes before applying its
bounds. Two baseline assertions fail: 2^43 and INT64_MAX produce 4 MiB instead
of the 16 GiB platform maximum. Valid and small inputs pass. The old negative
shift produced no sanitizer finding under this build's compiler flags; the
large-budget assertion failures are the reproduced evidence.

GetDbCacheSizeBytes in txdb.cpp now clamps MiB before multiplying to bytes.
AppInit2 calls the helper. Defaults, platform limits, and allocation splits stay
the same. Pure arithmetic tests avoid allocating the requested cache or touching
live data. Earlier helper-in-init.cpp builds failed due to startup stubs; the
existing database module avoids that linkage issue without changing the stubs.

- Normal and ASan/UBSan/leak runs: 8 init/database cases, 3,056 assertions pass.
- Normal and ASan separate zclassicd-mission candidates both build successfully.
- Compared relevant source files byte-for-byte between root and sanitizer tree.
- Evidence: mission/dbcache-module-before.log, dbcache-module-asan-before.log,
  dbcache-after.log, dbcache-asan-after.log and associated build logs.
- Production executable/inode hashes rechecked unchanged; no service action.

## Validated connection-budget conversion

init.cpp now clamps the 64-bit connection request to the platform
limit before narrowing it to int. New qa/rpc-tests/maxconnections.py covers nine
real startups, fresh regtest datadirs, loopback-only connections, disabled mining
and wallets, RPC readiness, and normal RPC stop.

- Baseline: three failures; 2^32 and INT64_MAX become zero, -2^32+1 becomes one.
  All nine baseline daemons exit zero with clean shutdown, isolating arithmetic.
  Evidence: mission/maxconnections-rpc-before/ and matching .log.
- Normal fixed matrix: all nine PASS. This host's cap is 873; large positives
  reach that cap, negatives clamp to zero, ordinary settings remain unchanged.
- ASan/UBSan/leak matrix: all nine PASS, all exit zero with clean shutdown and
  no sanitizer findings. Evidence: mission/maxconnections-{after,asan}/ and logs.
- Both candidates contain only the connection change after 073d1e5be. Source
  init.cpp compared byte-for-byte between normal and instrumented trees.

## Validated completed-startup shutdown path

An empty stopafterblockimport can finish before AppInit2 returns. The old final
return treated a pending stop as initialization failure, routing around the normal
main-thread-group join even though all initialization steps had completed. The
instrumented baseline reproduces this in seven of eight runs: exit one and worker
starts/interrupts after Shutdown begins. Eight normal baseline runs all passed;
the race depends on scheduling. No sanitizer finding occurred in these baselines.

AppInit2 now returns true after its final initialization step even with a pending
stop, selecting WaitForShutdown's normal interrupt/join path. Earlier failure
returns remain unchanged. The thread-ownership comment now describes the actual
code instead of a removed shutdown thread.

- qa/rpc-tests/stopafterblockimport.py: eight fixed normal and eight instrumented
  repetitions all pass with exit zero, import/init complete, and no late workers.
- Added invalid-maxblocksinflight control still rejects initialization and exits
  one before import, normally and instrumented. Its instrumented baseline passes.
- Both normal and ASan/UBSan/leak candidates pass the ordinary short-header wire
  fixture: all 129 blocks validate, counters clear, RPC stop exits zero, no peer
  or sanitizer errors. Relevant source files match between build trees.
- Evidence: mission/import-stop-{before,asan-before,after,asan-after}/,
  mission/import-stop-asan-invalid-before.json, and
  mission/import-stop-headers-{after,asan}/ with build/test logs alongside them.
- Production service, data and executable remain untouched.

Next: ordinary restart/cancellation resilience using only the existing 0..129
fixture in fresh temporary datadirs. Verify persisted tip/chainstate and graceful
worker cleanup through interrupted startup. No lifecycle test currently running;
all checks above completed before this milestone.
Do not duplicate completed security/scheduling campaigns or resume the stash.

## Validated PID-file ownership

A failed duplicate startup removed the active node's PID file despite failing the
datadir lock. The normal regression reproduces missing ownership after lock and
invalid-option failures; the isolated instrumented prototype also reproduces it.
The primary remains alive and RPC-responsive, and its chain is unchanged.

init.cpp now captures a PID path only after successful creation following the
datadir lock, and removes only that captured path. CreatePidFile checks write and
close results, always closes an opened FILE, and returns success/failure. PID-file
creation failure now produces an initialization error instead of being ignored.

- Normal and ASan/UBSan/leak: 9 init/getarg cases, all 73 assertions pass. Includes
  successful write, directory and missing-parent errors, and Linux /dev/full for
  buffered close failure. Unit binaries are test/test_bitcoin-mission.
- qa/rpc-tests/pidfile.py passes normally and instrumented: two failed duplicates
  preserve the active PID, the owner removes it on stop, and a PID path naming a
  temporary directory is rejected without deleting that directory. Primary RPC
  stays responsive and normal shutdown exits zero; no sanitizer findings.
- Evidence: mission/pidfile-before/, pidfile-after/, pidfile-asan/, unit/build logs
  and mission/pidfile-candidates.sha256. Relevant source files compared equal.
- src/zclassicd-mission and its ASan equivalent contain the PID milestone only.
  No production changes or excluded security tests were performed.

## Validated startup-failure worker join

Ordinary -onlynet=invalid with -par=2 starts a script-check worker and scheduler,
then rejects the local option. Three normal baseline runs abort (SIGABRT) after
Shutdown: done, with scheduler/mutex destructor assertions. A formal four-case
baseline (RPC off/on) has one abort and two late-scheduler failures. AppInit
interrupted its main thread group but did not join it on initialization failure.

AppInit now joins that interrupted group before calling Shutdown. Startup errors
still exit one; fully initialized stop-after-import exits zero. Comments about
thread ownership and separately managed bootstrap workers match the final code.

- qa/rpc-tests/startup-failure.py: all four fixed cases pass normally and under
  ASan/UBSan/leak checking. No abort, hang, late scheduler activity or sanitizer
  finding, with RPC both enabled and disabled.
- qa/rpc-tests/startup-cancel.py copies a completed, stopped 129-block test datadir,
  cancels during VerifyDB, and checks restart. Instrumented baseline fails for
  late scheduler activity; normal and instrumented fixes pass. Cancellation
  retains its exit-one status, all workers finish before Shutdown, then restart
  preserves exact tip 0000d77872aabab70015f08e2d138a35293ad0e5b671a5b6e8cad38c1b63aff4,
  clears download counters, and RPC stop exits zero. The source datadir is untouched.
- A normal stop-after-import plus early invalid-option control also passes.
- Evidence: mission/startup-failure-before/, startup-failure-matrix-before/,
  startup-failure-{after,asan-after}/, startup-cancel-{after,asan-after,asan-before}/,
  and startup-failure-stop-control/ with associated logs.
- Latest normal/instrumented candidates are zclassicd-failure in each build tree.
  Their driver/init source compared byte-for-byte. Older -mission binaries contain
  the prior PID milestone. Neither replaces src/zclassicd or the production inode.
- All build/test processes for this milestone completed. No production service,
  consensus change, or excluded security sequence was used.

Next: continue ordinary startup/restart and resource-lifecycle review from this
state. The primary synchronization fixes, historical block-478544 diagnosis, and
all completed peer/sanitizer evidence remain preserved. Do not resume the stash.

## Validated VerifyDB reconnect cancellation

The new bounded 130-block fixture reproduces a missing shutdown check during
VerifyDB's reconnect pass: both normal and ASan baselines run 129 reconnect
iterations after the first stop request, instead of one. Stored tip/coinbase
controls and subsequent full verification pass. Test-only shutdown state defaults
to false and is restored on fixture teardown.

VerifyDB now checks the shutdown flag after each reconnect, matching its backward
pass. A shared progress helper preserves percent-throttled RPC warmup messages.
The verification cache remains temporary; consensus and block acceptance do not
change. The full verification control emits 99 distinct progress messages.

- Normal selected tests: 11 cases, 1,015 assertions pass (includes scheduler).
- ASan/UBSan/leak isolated tests: 10 cases, 1,000 assertions pass (VerifyDB, init,
  getarg). Evidence: mission/verifydb-cancel-asan-isolated.log.
- The combined ASan run exposed a separate pre-existing scheduler use-after-free:
  wait_until retains a reference to a queue deadline while another worker erases
  that entry. Preserved in mission/verifydb-cancel-asan-after.log. This is the
  ordinary in-process manythreads test, not an excluded network/security sequence.
  No tool safety refusal occurred. Fix deadline ownership as a separate milestone.
- Normal and instrumented zclassicd-verify candidates build successfully. Normal
  and instrumented temporary-datadir startup cancellation/restart both pass:
  exact 129-block tip retained, download counters zero, clean shutdown, no
  sanitizer findings. Evidence: mission/verifydb-startup-cancel-{after,asan-after}/.
  Integration controls cancel in the backward pass; the new unit fixture
  specifically exercises reconnect cancellation.
- All VerifyDB build/test processes completed successfully before 8a11ae4eb.
  Scheduler changes are tracked separately below.
- Production, the paused stash, and all previous evidence remain untouched.


## Validated scheduler deadline ownership

The existing concurrent scheduler test exposed a heap-use-after-free in Boost's
wait_until: its deadline argument referred to the first queue entry, which another
worker erased while the mutex was released. A new shared-deadline regression
reproduces the same ASan finding before the fix. This API supports multiple workers;
the default daemon starts one scheduler worker, so this is not a claim of an
observed production crash.

The timed wait now uses a local value copied under the queue mutex. Wakeup,
drain, stop and task ordering semantics remain the same. Added ordinary tests
check 64 same-deadline tasks across eight workers execute once and never early,
and that a newly inserted earlier task can stop workers waiting on a later task.

- Normal and ASan/UBSan/leak: 13 scheduler/VerifyDB/init/getarg cases, all 1,084
  assertions pass. Evidence: mission/scheduler-deadline-{after,asan-after}.log.
- Separate TSAN build of scheduler.cpp and the two exact new test bodies passes
  69 assertions with halt_on_error enabled. Existing Boost libraries are linked
  without TSAN instrumentation; application scheduler/test code is instrumented.
  Evidence: mission/scheduler-deadline-tsan* and scheduler-standalone.cpp.
- Both zclassicd-scheduler candidates build. Normal and ASan/UBSan/leak four-case
  startup-failure worker cleanup controls pass, with no aborts or late worker
  activity. Evidence: mission/scheduler-startup-failure-{after,asan-after}/.
  All scheduler build/test processes completed before committing this milestone.
- Baseline evidence: mission/scheduler-deadline-before.log and the earlier
  combined mission/verifydb-cancel-asan-after.log. No excluded sequence was run.

## Validated seed-queue permit ownership

ProcessOneShot removed a queued seed destination before acquiring an outbound
permit. A full pool silently discarded pending discovery work. COneShotQueue
encapsulates the queue and lock, with the connector called outside that lock;
it now acquires a permit before taking a destination. Failed attempts still go
to the back of the queue, and successful connections retain permit ownership.
The production connector and network-selection rules are unchanged.

- Two deterministic queue/permit tests fail four assertions against the extracted
  original order in both normal and ASan builds. They cover a full pool and a
  failed connection waiting behind a connected peer.
- Fixed normal and ASan/UBSan/leak: 14 queue/scheduler/init/getarg cases, all 170
  assertions pass. Initial baseline test compilation needed explicit boolean
  casts for the legacy semaphore handle; failed build logs were retained.
- qa/rpc-tests/oneshot-queue.py uses two loopback seed listeners, one outbound
  permit, and ordinary version/getaddr/empty-addr exchanges. Baseline
  zclassicd-scheduler loses B after A completes, times out, then exits cleanly.
  Both fixed zclassicd-oneshot candidates connect B when A finishes, complete both
  seed exchanges, retain genesis height and zero block requests, and stop with
  exit zero. No peer errors or sanitizer findings. No blocks or external peers.
- Evidence: mission/oneshot-{before,asan-before,after,asan-after}.log,
  mission/oneshot-wire-{before,after,asan-after}/ and matching build logs.
- Candidate source files compare byte-for-byte across normal/instrumented trees.
  All queue milestone builds and tests completed. No production modification,
  paused security work, or tool safety refusal occurred.

Next: review remaining local resource-budget conversions. Some startup options
still narrow or multiply their signed input before validating it; use ordinary
configuration/unit tests in new datadirs for any concrete bug. Preserve consensus,
all successful synchronization evidence and the separate historical diagnosis.


## Validated pruning-budget validation

Pruning multiplied signed MiB input before checking it. The isolated startup
matrix reproduces five bad boundary outcomes: a huge positive and a negative
value wrap to an accepted 550 MiB target; other limits are disabled or report the
wrong error after wrapping. Five ordinary controls pass. All cases deliberately
stop on -onlynet=invalid before opening any block database; no pruning is done.

- New qa/rpc-tests/prune-budget.py, ten cases. Its first attempt was stopped early
  by auto-generated txindex=1 in the fresh configuration. The isolated matrix now
  passes -txindex=0 explicitly. Preserve both baseline logs/directories.
- init.cpp now isolates InitPruneMode and validates negative, maximum signed-byte
  capacity, and minimum target before committing its state. Multiplication is
  then bounded. Valid budgets and zero remain unchanged; overflow is rejected.
- Normal and ASan/UBSan zclassicd-prune candidates build successfully.
  Both final ten-case matrices pass with leak checking and no sanitizer findings;
  every case confirms its temporary block database was never opened.
  Evidence: mission/prune-budget-{after,asan-after}/ and corresponding logs.
  No root service executable is overwritten.
- Baseline: mission/prune-budget-before-isolated/ (5/10 pass, all block DBs unopened).
  Builds: mission/prune-daemon-{build,asan-build}.log. All work for this milestone
  completed before commit; normal and instrumented init.cpp compare equal.
- Separate static review finding: first config read catches any std::exception
  and opens the existing config for replacement. Investigate ordinary local
  config-error handling without touching production settings or authentication.


## Validated configuration read/error handling

The first config read caught all std::exceptions and opened the config for
replacement. A simple local syntax typo replaced the file with generated defaults
instead of reporting the error. Valid existing files were also read twice,
appending every list option twice; one addnode appeared twice in RPC.

ReadOrCreateConfig now reads an existing config once. Syntax errors reach the
existing startup error handler. Only missing-file errors trigger creation, with
an existing-path guard and checked write/close results. Default contents are
unchanged; no authentication behavior or production configuration was modified.
This addresses ordinary error handling, not an atomic first-creation guarantee.

- New qa/rpc-tests/config-load.py: both normal baseline cases fail (file replaced;
  duplicate configured peer). Fixed normal and ASan/UBSan/leak four-case matrices
  pass, including first creation and missing-parent write failure.
- The typo file is byte-for-byte unchanged; getaddednodeinfo lists exactly one
  configured loopback destination and RPC stop exits zero. Creation/error controls
  stop before opening a block database. No sanitizer findings.
- Evidence: mission/config-load-{before,after,asan-after}/ and associated logs.
  Both zclassicd-config candidates build and source bytes match. All jobs complete.
- Production PID 503646 and both binary hashes rechecked unchanged at 02:34 UTC.
  Root datadir, service, paused stash and historical validation evidence untouched.

Next concrete finding: the auto-generated config explicitly writes txindex=1,
even though that is the source default. This makes first-run -prune fail the
explicit-txindex conflict check, defeating its intended automatic interaction.
Use fresh genesis-only datadirs to verify removal of the redundant generated
setting preserves normal indexing and permits the requested pruning mode. Never
prune existing data or change a user's existing configuration.


## Validated first-run pruning defaults

The new qa/rpc-tests/prune-defaults.py confirms first-run pruning fails because
the generated config makes the source's txindex default explicit. The normal
unpruned baseline starts/restarts with indexing enabled but fails the new implicit
setting assertion. Explicit txindex=1 plus pruning correctly fails and preserves
that operator-provided file.

- Removed only the generated txindex assignment; normal source default remains
  true, and the existing pruning interaction can soft-set it false. Existing
  configuration files and authentication settings are unchanged.
- Both zclassicd-defaults candidates build. Normal and ASan/UBSan/leak matrices
  pass all three scenarios: pruned/unpruned startup and restart at genesis, plus
  explicit conflict. All five startups per build complete as expected, with no
  block deletion or sanitizer findings. All processes completed.
- Evidence: mission/prune-defaults-{before,after,asan-after}/ and associated logs.
- Relevant candidate sources compare equal. All checks completed before commit.
- Next resource finding: -par is narrowed to int before applying its existing
  64-thread cap. Large positive/negative values can change sign or become auto.
  Keep it signed 64-bit until after bounds, and use ordinary isolated startup
  checks (no blocks/mining/production access) if pursuing this task.


## Validated script-thread budget conversion

The -par input narrows to int before the existing 64-thread cap. New
qa/rpc-tests/script-threads.py exercises eight startup budgets, including positive
and negative 64-bit boundaries. It reuses startup-failure.py's owned-process
cleanup matrix through a new optional script_threads argument (default unchanged).
Each case deliberately stops at -onlynet=invalid before opening a block database;
workers remain idle and are joined. No script-validation work/mining is performed.

Normal baseline against zclassicd-defaults reproduces all four boundary failures:
positive values become 2/0 workers; negative values become 2. All four ordinary
controls pass and all processes cleanly exit. Source now retains int64_t through
core adjustment and the existing 64-thread cap, narrowing only the final value.

- Both zclassicd-threads candidates build. Normal and ASan/UBSan/leak matrices
  pass all eight cases with no sanitizer findings, late workers or open block DBs.
- Evidence: mission/script-threads-{before,after,asan-after}/ and matching logs.
  Normal/instrumented init.cpp compare equal; all jobs completed before commit.
- A subsequent independent HTTP work-queue review is uncommitted. Its original
  queue class was extracted without behavior changes into http_workqueue.h for
  ordinary in-process lifecycle tests. Baseline normal/ASan/TSAN tests are now
  running; no existing socket/malformed-message fixture is executed. The standalone
  test initially needed an explicit boost/thread.hpp include; build logs retained.
- Static concerns: an unlocked stop-flag read, accepting work after interruption,
  and detached worker ownership. Do not claim a fix before reproducing/validating.
- Production and the paused stash remain unchanged. No tool safety refusal occurred.


## Validated HTTP work-queue interruption

The original WorkQueue template is extracted into http_workqueue.h for ordinary
in-process tests, with no HTTP server or sockets involved. A new regression
reproduces accepting tasks after interruption (two assertions fail normally and
under ASan). The worker loop also reads running outside the mutex used by Interrupt.

The queue now rejects work when stopped and checks running only under the queue
mutex. Existing accepted-task ownership, capacity and callback execution remain
unchanged. Detached worker registration/lifetime is a separate pending review.

- Initial TSAN fixtures joined immediately after interruption and did not report
  the flag race, at either -O1 or -O0. The final test observes worker exit before
  joining, avoiding synchronization inside the thread library during the access.
  TSAN then reproduces the read/write race against the preserved original header.
  Evidence: mission/http-workqueue-tsan-baseline-exit.log (exit 66).
- Final normal and ASan/UBSan/leak: eight queue/scheduler/seed-queue cases, all 112
  assertions pass. Evidence: mission/http-workqueue-{final,asan-final}.log.
- Final TSAN: all three queue tests and 15 assertions pass with halt_on_error.
  Both zclassicd-workqueue candidates build; normal and instrumented startup-failure
  controls (RPC off/on) pass, with clean exits and no sanitizer findings.
  Evidence: mission/http-workqueue-tsan-final.log and workqueue-startup-{after,asan-after}/.
  All build/test processes completed; relevant source files compare equal.
- No existing HTTP socket-lifetime or malformed-message suite was executed.
  All test tasks are ordinary local callbacks. No tool safety refusal occurred.
- This milestone is ready to commit. Disk free ~5.4 GiB; archive older generated
  candidates with verified hashes before creating further full daemon candidates.
  Next: examine worker ownership independently, using only ordinary in-process
  lifecycle tests. Do not run the excluded socket/malformed-message sequence.


## Candidate archives and active HTTP worker ownership

Six older generated executables (fallback, mission, failure in normal/ASan trees)
were compressed into adjacent .gz archives. Each archive was decompressed and
SHA256-verified before removing its uncompressed generated file. Repository
tracking and executing-inode checks confirmed the files were disposable build
outputs, not tracked files or running processes. All archives were synced.
The full hashes, sizes, modes and mtimes are recorded in
mission/candidate-archives-20260914.jsonl. All data remain recoverable; logs,
source, current candidates, production, and backups were untouched. Free ~6.6 GiB.

Next test: shutdown can miss a launched HTTP worker delayed before Run increments
its active counter. The queue now has a Start helper that retains thread handles
and performs caller-supplied per-thread initialization; production does not use
it yet. WaitExit still uses the original active counter for the baseline. The
new helper's destructor joins retained handles so the regression can demonstrate
an early WaitExit safely, without freeing memory under a live worker.

New in-process test gates worker initialization and observes whether WaitExit
finishes before that gate opens. No server, sockets, requests or credentials.
Standalone normal baseline build is running; changes in http_workqueue.h and
http_workqueue_tests.cpp are uncommitted. ASan tree still has the committed queue
interruption snapshot. Source-group Start/WaitExit lifecycle calls are sequential.
After reproducing, replace the counter with joins of owned handles, route the
production thread initializer through Start, and preserve thread naming.


## Validated HTTP worker ownership

The delayed-initialization fixture reproduces an early WaitExit with two failed
assertions against the original active-worker counter. The test retains handles
for safe cleanup, so no live queue is destroyed during baseline reproduction.

WorkQueue now owns a thread group and joins launched handles, including workers
still initializing. Removed ThreadCounter/numThreads and detached worker startup.
The production Start callback keeps the existing zcl-httpworker name. Destruction
interrupts and joins owned workers before disposing pending tasks; direct Run
callers retain their existing obligation to join their own thread. StopHTTPServer
also clears its deleted queue pointer.

- Normal and ASan/UBSan/leak: nine queue/scheduler/seed-queue cases, all 116
  assertions pass. Standalone TSAN: four queue cases, 19 assertions pass.
- Baseline: mission/http-worker-ownership-before.log. Final evidence:
  mission/http-worker-ownership-{after,asan-after,tsan}.log. No sockets involved.
- Both zclassicd-httpworkers candidates build. Normal and instrumented startup
  controls (RPC off/on) and a successful RPC request/stop smoke all pass. Normal
  stop exits zero, no late workers or sanitizer findings. Evidence:
  mission/httpworkers-integration-{after,asan-after}/. The private composition
  harness is mission/httpworkers-integration.py, using committed QA helpers.
  All build/test processes completed; relevant source files compare equal.
- A final mutex-comment clarification does not change the tested code. New
  daemon builds include it; normal and ASan header copies match.
- No production action, excluded sequence, authentication change, or tool refusal.


Next resource review: HTTP startup narrows rpcworkqueue and rpcthreads from a
signed 64-bit argument to int after only applying a lower bound. Large settings
can wrap into an oversized queue limit or no worker threads. Use ordinary startup
fixtures and safe boundary values; do not attempt to create billions of workers.
Keep validation before HTTP resource allocation/startup and preserve the existing
minimum-one behavior for nonpositive settings. No authentication or protocol
changes are needed. No new task source changes yet.


## HTTP resource-budget validation

InitHTTPServer now validates -rpcworkqueue and -rpcthreads as int64 values before
allocating HTTP resources, rejecting values above INT_MAX. It preserves the
existing minimum-one behavior for nonpositive values and all representable
positive settings. StartHTTPServer uses the validated worker count. No arbitrary
low resource cap, authentication, protocol, or consensus change was introduced.

qa/rpc-tests/http-budgets.py covers twelve ordinary startup settings in fresh
datadirs, stopping before block databases open. startup-failure.py accepts optional
extra_args with existing callers unchanged. Baseline zclassicd-httpworkers failed
six overflow cases: INT_MAX+1, 2^32+2, and INT64_MAX each narrowed to incorrect
queue depths or thread counts. All baseline cases were chosen to avoid allocating
large worker pools; an INT_MAX queue capacity does not preallocate queue items.

Both normal and ASAN/UBSAN/leak builds now pass all twelve cases, exit cleanly
with the expected startup error, remove their PID file, and leave block databases
unopened. Evidence: mission/http-budgets-{before,before-boundary,after,asan-after}/.
Normal and sanitizer ordinary RPC startup/request/stop controls also pass with
exit zero and no sanitizer findings; evidence is under
mission/http-budgets-rpc-{after,asan-after}/. Production remains untouched.

## Import/download scheduler pause handling

The normal and ASAN baselines reproduced both import and reindex failure paths:
129 owned requests remain while ordinary replies are ignored, then both peers
time out, preferred eligibility is lost, and the preferred peer cannot resume.
Each baseline fails 16 assertions across two deterministic cases. Evidence:
mission/import-pause-{before,asan-before}.log. No production or socket fixture
was involved; these are ordinary valid-block in-memory transport tests.

main.cpp now separates ReleaseBlockRequests from terminal StopBlockDownload.
SendMessages releases requests and active header sync while local import/reindex
is paused, preserves preferred eligibility, and suppresses new block downloads.
The new test repeats three pauses, visits the inbound peer first on resume, and
requires the preferred peer to acquire 128 requests immediately and then validate
the complete 129-block fixture. Both normal and ASAN/UBSAN/leak builds pass seven
selected ordinary download cases and 4,829 assertions, including RPC accounting,
timeout/reconnect takeover, header completion and teardown controls. Evidence:
mission/import-pause-{after,asan-after}.log.

Both normal and sanitizer loopback short-header fixtures also pass: A owns 128 requests, its
ordinary disconnect releases them, B delivers/validates all 129 blocks, all
accounting clears, both peers report no errors, and RPC shutdown exits zero.
Evidence: mission/import-pause-wire-{after,asan-after}/. No sanitizer findings.

Scope: pause handling is observed in the peer scheduler. Follow up on short import
intervals that may start/end between scheduler visits, and on publication of the
existing cross-thread import flags. Do not conflate that review with completed
coverage. No consensus or validation rules changed.

Production PID 503646 and its executable inode were verified unchanged again at
06:06 UTC: running SHA 6c4a80ec792c894aa1be9d27332f7d05e857e36408485e3b651fe114f3be14ad;
on-disk src/zclassicd SHA bc161f5339039ca1bacd1653dd45c2b42f409c4982b029609e8316869cca3c4f.
No restart, deployment or production datadir changes were performed.


## Import entry ownership, publication and genesis reindex

CImportingNow now lives in importing.h, publishes fImporting atomically, and
releases all peer requests and active header roles under cs_main before importing
block-file contents. fReindex is also atomic. The guard cannot be copied and
restores the flag on scope exit/unwinding. Preferred eligibility is retained.
This covers short imports that begin/end between peer scheduler visits.

A deterministic short-import baseline failed six assertions: 128 requests and
one header role survived import, causing timeout/disconnect at the next visit.
The new ordinary fixture repeats three short imports with no scheduling inside
those scopes, then verifies immediate fresh requests and validation through 129.
Evidence: mission/import-entry-before.log and mission/import-entry-final.log.

A focused TSAN harness using the actual guard reproduced its old bool write
racing a concurrent reader: mission/import-publication-tsan-work-before.log,
exit 66. An initial empty scope was optimized enough to miss the race; the final
regression yields within the scope to represent nonempty import work. Both guard
and publication cases now pass six assertions under TSAN. This focused harness
stubs request cleanup; the ordinary download tests exercise the real cleanup.

qa/rpc-tests/import-blocks.py verifies the fixture digest, creates its own datadir,
imports with -loadblock/-stopafterblockimport, restarts and checks the exact tip,
reindexes only that new datadir, then restarts and checks the tip again. This
found an existing SIGSEGV during genesis reindex, reproduced by both the prior
bb281eb0d candidate and the initial new candidate. A separate copied test datadir
under gdb traced it to AcceptBlockHeader dereferencing the null genesis parent.
UBSAN independently confirmed the null member call. Evidence:
mission/import-entry-files-{baseline,after,asan-baseline}/ and
mission/import-entry-reindex-debug/gdb.log. All failed datadirs/logs are preserved.

The unconditional parent check dates to d57bf7a5e1 (2019-08-30); its parent source
already accepted the configured genesis with no parent. The failed-ancestor
lookup now runs only when a parent exists. Every existing header, contextual,
transaction and block check remains intact. Non-genesis headers still require a
known parent and run the same failed-ancestor checks. No consensus rule changed.
A direct genesis-header/duplicate-header regression is in CheckBlock_tests.

Final normal and ASAN/UBSAN/leak selections both pass 11 cases and 5,566 assertions,
covering genesis, import scopes/publication, both scheduler pause modes, short
imports, preferred takeover/reconnects, role diagnostics, teardown and header
completion. Evidence: mission/import-entry-{final,asan-final}.log. Normal and
instrumented candidates both pass all four file-import/reindex/restart phases,
retain the exact tip at 129, clear all request counters, and exit zero with no
sanitizer findings: mission/import-entry-files-{fixed,asan-fixed}/. Changed source
bytes were compared across the normal and ASAN trees. The initial helper linkage
mistake was corrected before these final checks; its failed build log remains.

Eight older untracked, nonexecuting generated candidates (config, defaults,
prune and threads for normal/ASAN) were compressed into new exclusive-created
archives, verified by decompressed SHA, and recorded in
mission/candidate-archives-20260914.jsonl before removing uncompressed copies.
Files and directory entries have been fsynced. No source, log, wallet, production
file or existing backup was removed or overwritten. Headroom is about 5.3 GiB.

Next review: outbound address selection currently ends its search when the first
candidate belongs to an already-connected group or a local address. Check whether
eligible candidates can be considered within a strictly bounded selection cycle
while retaining network diversity and retry/port policy. No changes there yet.
