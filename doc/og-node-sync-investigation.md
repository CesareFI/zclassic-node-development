# OG Zclassic sync investigation, 2026-09-13

The original node has two independently reproduced problems. The download
accounting defect prevents timely peer recovery. Separately, its transaction
size check rejects the next historical block. Fixing the former alone cannot
make this node sync.

## Preserved failure state

Before a restart or configuration change, the mission captured RPC responses,
peer directions/services/versions and requests, sockets, host process and thread
state, resource usage, systemd configuration and journal, Git state, compiler
configuration, and binary hashes. The private evidence directory is
`mission/20260913T000007Z`; it is not a release asset.

The base commit is `14a83d510ffd109d3fa09bf74ebf8c28854a263f`. The original
daemon SHA256 is
`dbb75b665c11dc5d62553300463981c577910a102a9dfe56720059cc84af0d15`.

The live active height was 478543 and the header height 511175. One inbound
peer owned requests for 478544 through 478671. The other inbound peer advertised
no full-node service. There were no outbound connections. Mining was disabled.

Read-only debugger inspection found 128 actual entries in `mapBlocksInFlight`
but `nQueuedValidatedHeaders == 5081`: 4953 counted requests did not exist.
The oldest request was made at 2026-09-12 17:38:57.407856 UTC, with a deadline
of 2026-09-14 22:38:57.407856 UTC, a 53-hour allowance.
`nStallingSince` was zero. The outbound semaphore had 15 free permits, and
deeper thread stacks showed ordinary timed sleeps, not semaphore exhaustion.

## Download accounting and recovery

Previously, `FinalizeNode` erased a peer's entries from `mapBlocksInFlight`
but never subtracted its validated requests from `nQueuedValidatedHeaders`.
Normal receipt did subtract them. Repeated teardown therefore permanently
inflated the count used by `GetBlockTimeout`, including the calculation intended
to shorten an excessive deadline. Header traffic does not reset the block
deadline; it merely makes a connection appear active while this inflated
deadline has not expired.

This source tree uses per-request `nTime` and `nTimeDisconnect`; it has no
`nDownloadingSince` field. `nStallingSince` belongs to the separate download-window
stall detector.

The 128-request limit is not itself the root cause. With only one usable block
source, the separate download-window stall detector need not activate.

`StopBlockDownload` now drains outstanding requests through the same accounting
path as receipt, releases header-sync and preferred-download roles, and supports
repeated cleanup. Timeout handling invokes it before object destruction, so a
healthy peer can take over even while other references retain the old peer.
`FinalizeNode` uses the same cleanup and tolerates repeat finalization.
The socket thread also signals cleanup immediately after removing a connection,
outside the peer-list lock. This covers remote and administrative disconnects
even when another reference postpones destruction. A terminal download-state
flag prevents queued messages from reviving request or header-sync roles.

The deterministic test uses real OG blocks 0–129, not generated blocks. It
feeds valid headers to A, records its 128 requests, lets B supply block 129,
and continues header traffic from A while advancing a test request clock.
After timeout B takes over blocks 1–128 and normal block processing advances
`chainActive` to 129, without a daemon restart or destruction of A's object.
A separate test checks teardown accounting after repeated peer churn.

Both tests failed before the cleanup fix (14 failed assertions) and passed
after it. The deterministic test uses an in-memory outbound transport.
A separate real-socket test (`qa/rpc-tests/og-download-stall.py`) also passed:
A sent eleven header messages while withholding 128 requested blocks, timed
out after 300.11 seconds, and B supplied all blocks through 129 without a
restart. The isolated daemon stopped through RPC with exit status zero.
With two preceding peer teardowns, each holding 128 requests, the same socket
test failed on the preserved original daemon (no recovery within 390 seconds)
and passed on the fixed daemon (A disconnected after 300.14 seconds). Both
processes stopped normally through RPC.

An isolated build with address and undefined-behavior sanitizers passed the
15 download, main, and denial-of-service cases, including leak detection.
The sandbox's tracing prevented LeakSanitizer from running; the full test was
therefore repeated on the host and exited successfully. Dependency coverage
is limited to the code built with sanitizer instrumentation. The latest socket
lifecycle, outbound ownership, scheduling-limit, and RPC changes subsequently
passed all 30 selected download, RPC, main, and denial-of-service cases with
ASan, UBSan, and leak detection enabled (51.03 seconds, exit zero).

## Block 478544 and historical validation

The locally accepted header hash is
`0000000008e4ec6ac2f23b017f38ae68e932a3c2d272ea08c9fbdf75409783a3`.
At initial capture its index had tree validity, no block data, and no invalid
flag. Two different seed addresses returned identical 127435-byte block
payloads, SHA256
`a8e3c25ba4e604560fa91d9ef25ebaef5d5223472926ab03de0c7a4ea9170357`.
Both advertised the same software revision; separate addresses do not prove
independent administration. The header and payload agreement is corroboration,
not a replacement for consensus validation.

Feeding this existing block to the live daemon's normal P2P block handler
produced `REJECT_INVALID` with **`bad-txns-oversize`**. The active chain did not
advance. `CheckTransactionWithoutProofVerification` applies
`MAX_TX_SIZE_AFTER_SAPLING == 102000` regardless of historical height. This
preliminary failure occurs before full contextual/UTXO validation. A separate
strict historical validation, described below, establishes that the block is
valid under the earlier rules.

Repository commit `8d6d05e632c5ede0bc4cac320f6b70f966303b9d`, dated 2023-07-21,
changed the post-Sapling transaction bound from 2000000 to 102000 bytes and
the block bound from 2000000 to 200000 bytes. That commit introduced no height
activation condition. Block 478544 predates the change by years. Simply raising
the modern bound, selecting an invented activation height, or bypassing a
validation check is not an acceptable resolution.

The current mission has requested clarification of whether restoring verified
historical validation rules is allowed under its prohibition on consensus
parameter changes. No consensus parameter or validation rule has been changed.

The ban list contained both seed addresses despite their demonstrated ability
to serve the requested block. After deployment, the journal directly recorded
the size rejection, CheckBlock failure, and bans of those serving addresses.
Thus the validation failure also removes useful block sources. The original
unlogged bans cannot individually be attributed with certainty. No blanket
unban has been performed.

The native transaction deserializer reports that the block's second transaction,
`e3eeb123a79945cc74e6107422b124dc130ddd4b61fe5c74087317c256c79700`,
is 125811 bytes, version 4 with the Overwinter flag and 74 JoinSplits. It has
no Sapling spends or outputs. The block's computed Merkle root matches its
header. These checks locate the size failure but do not establish full
contextual or proof validity by themselves.

The pre-reduction source `42d81ed963f5eab84db6bdb71d3bdf05038ad8f0`
was built with only compiler/header and Boost filesystem compatibility edits;
its main validation, consensus, transaction, and chain-parameter sources were
unchanged. In a disposable copy of the consistent production snapshot, normal
`submitblock` accepted this block in 1.189 seconds and advanced from 478543 to
the expected 478544 hash. `-checkpoints=0` disabled the checkpoint-ancestor
trust optimization, forcing expensive proof and script checks. Mining remained
off and RPC shutdown exited zero. Evidence is in
`mission/historical-validation/result.json`; no state was copied back to
production. This proves historical validity, without making the old validator
a safe substitute for current-network validation.

A separate read-only P2P probe fetched and checked every parent link from
478544 through the pre-reduction source's checkpoint at height 2013514,
`000019679aa2ea97a3f18bd9265bc91a09929ea0b1acc0fc5ef77cdf3cf906e7`.
An independent verifier rehashed all 1,534,971 retained header preimages and
confirmed that checkpoint. The 940,423,793-byte transcript SHA256 is
`9c3ef5e2125683ed5557b0744b2e37358d32dbb4829ca1355a83907b380e57f2`;
evidence is in `mission/checkpoint-ancestry-2013514`. This establishes the
blocked header's membership in the checkpoint-anchored chain. Full block
validity is established by the separate strict historical validation above.

The [July 2023 release notes](https://github.com/ZclassicCommunity/zclassic/releases/tag/v2.1.1-58)
announce the smaller block limit but give no activation height. Neither those
notes nor the source change establishes a height boundary for a compatibility
correction. A release timestamp or preceding checkpoint is insufficient.

## Hypothesis status

| Hypothesis | Evidence/status |
|---|---|
| A stalled peer keeps all 128 requests indefinitely | Hours-long retention proven; deadline is finite (53 hours), not literally infinite. |
| Teardown leaks global request accounting | Proven in source, live memory, and deterministic regression. |
| Stale accounting inflates future timeouts | Proven in source and regression; live inflated counter and deadline captured. |
| Headers hide lack of block progress | Headers continue without progress; they do not directly reset the block deadline. |
| Abandoned requests are not immediately reassigned | Previously retained until finalization; timeout cleanup and B takeover tested. |
| No usable outbound peers during IBD | Zero outbound captured; reachable seed peers are banned; semaphore exhaustion ruled out. |
| Block 478544 fails normal validation | Exact current rejection is `bad-txns-oversize`; strict historical validation accepts it, including proofs and scripts. |
| Sapling/Overwinter compatibility involved | Post-Sapling size bound is involved; strict historical proof and branch-ID checks pass. |

## Shutdown

The original journal records an empty `MAINPID` causing
`ExecStop=/bin/kill -TERM $MAINPID` to fail, and a previous shutdown ending in
SIGKILL. The original unit is backed up in the evidence directory.

The installed unit in `contrib/systemd/zclassic.service` supervises foreground
execution, stops through `zclassic-cli`, allows 15 minutes for flushing, and
disables escalation to SIGKILL. A separate temporary datadir test using the
original daemon exited normally via RPC stop in 0.52 seconds with mining off.
The unit passed `systemd-analyze verify`. Production then stopped gracefully
under its actual database load in approximately 17 seconds, with systemd
Result=success and exit status zero. A consistent blocks/chainstate snapshot
was copied while stopped for isolated diagnosis. Production restarted under
foreground supervision with the networking fix and new RPC counters; its
height remains 478543 because the separate size rejection is unchanged.

## Remaining acceptance work

The production node is not fixed yet. A justified historical compatibility correction,
continued production progress past the next 128-block boundary,
sustained useful outbound connections, sanitizers, and the 16/32/64/128 performance
comparison are still required. No chainstate or block files have been deleted.

## Additional peer lifetime safety

The `setban` RPC previously repeatedly looked up the first matching peer until
the socket thread removed it. It also used that borrowed pointer outside the
peer-list lock. The corrected traversal holds the lock and marks every matching
peer once. `disconnectnode` now holds the same lock from lookup through use,
and outbound creation now refuses duplicate connections without acquiring an
extra reference. Previously that path incremented a reference that had no
matching release. New peers receive their network ownership, one-shot flag,
and outbound permit before publication to the socket thread. `ConnectNode`
returns a success flag so the caller does not dereference a peer that might
already have disconnected. Disconnect flags and reference counts are atomic;
reference release asserts against underflow. These changes do not alter consensus or ban policy.

A regression keeps connected peer objects alive and listed while invoking the
RPC. Before the traversal fix it timed out after 20 seconds; afterwards it
returns and flags both matching peers while leaving an unrelated peer connected.
A duplicate-connection regression failed before the ownership fix with two
assertions, including a reference count of 1 instead of 0; it passes afterwards.
The RPC and download suites pass together. An additional seeded 1000-operation
test derives its accounting model from emitted block requests, interleaves
cross-peer and duplicate block deliveries with repeated peer finalization, and
checks all per-peer and global counters after every operation. It passes. This is not a claim that all legacy
networking data races have been eliminated.

## Operator report

Run `python3 contrib/diagnostics/sync-status.py --datadir=/root/.zclassic` for
active/header heights, IBD, connection directions, peers holding block requests,
request ages, remaining deadlines, stall duration, and global counters.
Use `--json --watch=60` for one machine-readable sample per minute. It uses
read-only RPCs and does not change node state. Preferred-download eligibility
and peers actually holding requests are reported separately. When no peer
exists, the current RPC cannot expose global counters and the report leaves
those values unknown instead of assuming zero on older builds. The new
`getblockchaininfo.blockdownload` object exposes global request counts,
preferred-download and header-sync peer counts, and the configured request
limit even with zero peers.

## Bounded scheduling and further verification

`-maxblocksinflight` accepts integers from 1 through 128; its default remains
128. The ordinary download scheduler and direct inventory-request path use
the same startup-only bound. Nine invalid arguments, including overflow and
trailing junk, are rejected before database startup. Parameterized tests verify
request caps and normal block recovery at 16, 32, 64, and 128.

The real socket test also passes with both A and B dialed through `addnode`:
both are outbound preferred-download peers, A times out after 300.08 seconds
while continuing header traffic, and B advances the chain to 129 without a
restart. Two distinct loopback IPs respect the existing connection-per-IP
policy. No production peer-selection policy was relaxed for the test.

The larger benchmark fixture contains 4096 consecutive OG blocks copied from
the frozen snapshot (SHA256
`4a382be44d8add0f95c17e4bc6eb8a414cf3e37b38779a95c738f42fec9bbdd3`).
An initial smoke run reached 4033 within 180 seconds while compilation competed
for CPU, then stopped cleanly at the harness deadline. This is not a valid
limit comparison. The short harness test passes at all four limits.

Twelve controlled runs (three per limit) subsequently passed through height
4095 and stopped normally. The first harness models a serial 100 ms service
delay per `getdata` batch, with block payloads capped at 1024 KiB/s per peer.
Its median timings and observed peaks were:

| Limit | Median seconds | Peak RSS MiB | Largest served-height gap | Longest sampled pause, seconds |
|---|---:|---:|---:|---:|
| 16 | 204.25 | 93.88 | 20 | 0.58 |
| 32 | 202.91 | 94.14 | 49 | 0.57 |
| 64 | 199.33 | 94.06 | 112 | 0.61 |
| 128 | 154.91 | 94.69 | 298 | 3.78 |

All runs had zero duplicate requests and zero swap usage. Each received
34,526,258 P2P bytes, including header traffic. Median daemon CPU time ranged
from 130.34 to 132.74 seconds. The larger limit improved throughput under this
service-delay model, with larger gaps between served blocks and the active tip.
The raw samples, manifests, preserved harness, and CSV/JSON summaries are in
`mission/bench-4096-healthy` and `mission/bench-service-harness.py`.

Serial service delay differs from pipelined network latency. The revised
harness adds a bounded response queue with deadlines measured when requests
arrive, and locks complete frame writes across its receive and send threads.
All four short-fixture smoke tests pass under this latency model.
Twelve full pipelined-latency runs also pass, using the same fixture, 100 ms
response delay, and 1024 KiB/s per-peer payload limit:

| Limit | Median seconds | Peak RSS MiB | Largest served-height gap | Longest sampled pause, seconds |
|---|---:|---:|---:|---:|
| 16 | 96.78 | 93.60 | 50 | 0.51 |
| 32 | 96.01 | 93.90 | 93 | 0.51 |
| 64 | 98.29 | 94.22 | 188 | 0.54 |
| 128 | 97.66 | 94.71 | 351 | 1.38 |

Each run normally validated blocks through 4095, received 34,526,194 P2P bytes,
and stopped through RPC with exit zero. No duplicate requests or swap usage
were observed. Median daemon CPU time was 127.85–129.97 seconds; host CPU
steal was zero. Median other-process CPU time was 5.33–6.89 seconds per run,
including the harness, RPC clients, and production node. No builds or other
heavy tests ran concurrently.

These runs used daemon SHA256
`6c4a80ec792c894aa1be9d27332f7d05e857e36408485e3b651fe114f3be14ad`
and the preserved harness `mission/bench-latency-harness.py`, SHA256
`0990fd622e7df78d5b5b7f1ed872d81c7a7c6d4e094e268388e0ae2eda9e021c`.
Samples and summaries are in `mission/bench-4096-latency`. Pipelined throughput
is similar across limits in this workload, while larger limits allow more
received blocks to accumulate ahead of the active tip. Three repetitions and
early-chain blocks do not establish an Internet-wide optimum. Stalled-peer
comparisons remain pending; the production default remains 128.

A package installation caused `needrestart` to restart production automatically
at 07:08 UTC. The unit stopped through RPC, logged shutdown completion, and
systemd reported success; mining remained off. It loaded the already tested
limit-option build, SHA256
`84732b84c233277dd2a16aea5674dab0ce2c08aa6e331c1f99442035c82d67b9`.
Subsequent package installations must set `NEEDRESTART_MODE=l` to prevent
unplanned restarts.

The validated networking build at `e9fa74638` was deliberately deployed at
10:11 UTC after preserving another diagnostic snapshot and the service file.
RPC shutdown completed in 6.74 seconds; systemd reported success. The running
binary SHA256 is
`6c4a80ec792c894aa1be9d27332f7d05e857e36408485e3b651fe114f3be14ad`.
Post-deployment verification confirms the retained active tip, mining disabled,
and the new global download counters. A verifier initially misparsed the CLI's
plain-text block hash; a corrected read-only verification passed without another
restart. Production still rejects the historical transaction size; deployment
of the networking fixes does not establish full synchronization success.

## Further protocol and iterator verification

The `addnode` retry loop erased connected entries, then decremented the returned
iterator even when it was `begin()`. An extracted traversal with checked STL
iterators aborts on the original loop and passes after replacement with
`list::remove_if`. A real outbound test runs across repeated two-minute retry
cycles, recovers from A after 300.14 seconds, advances through block 129, and
stops normally. No link to the original production stall is claimed for this
separate undefined-behavior defect.

A 512-case seeded test fragments malformed frames while their sender owns block
requests. It exercises oversized lengths, bad magic/checksums/commands, and
truncated header/block payloads through the actual receive path, repeats
teardown, then verifies healthy recovery through block 129. It passes normally
and under ASan/UBSan with leak detection.

Block and transaction reject messages also serialized the validation code as
four bytes, causing a normal decoder to read an empty reason and the wrong
hash. Two decoder regressions fail six assertions before the correction and
pass afterwards. The three network serialization sites now emit one byte;
validation results, internal-code filtering, reasons, and ban scores are
unchanged. All 33 selected tests pass normally and with ASan, UBSan, and leak
detection (59.25 seconds for the instrumented run).

Extending the benchmark fixture exposed historical blocks exceeding today's
200000-byte block limit: heights 6587 (226001 bytes), 6590 (310839), 6591
(377298), 7612 (200209), and 7653 (372290). These are framing/size findings from
the frozen block file, not a new full-validation result. A separate 4609-block
fixture exercises the 4096-block download window without mixing that historical
size incompatibility into the networking test.


The socket-thread connection notification now uses a peer-count snapshot taken
under `cs_vNodes`, avoiding an unlocked vector-size read concurrent with
outbound insertion. The normal and instrumented 33-case suites and all four
short socket tests pass for this correction.

Four further cases exercise the near-tip inventory request path before headers
are known, at each configured limit. They check repeated announcements,
duplicate receipt, mixed unvalidated/validated requests, repeated cleanup, and
healthy takeover with normal block validation. All 37 selected tests pass
normally (43.04 seconds) and with ASan, UBSan, and leak detection (71.80 seconds).

The first long stalled-peer benchmark stopped early when a five-second RPC
sample timed out during chain activation. A had disconnected, B had delivered
all 4095 blocks, and global request counters were zero. The diagnostic RPC
observed height 583; shutdown reached 720 and exited normally. This run is
preserved as a failed benchmark in `mission/bench-4096-stalled`. The harness now
records temporary RPC transport unavailability and retries within the same
600-second overall deadline. Application errors, peer errors, daemon exit,
and failure to reach the target remain failures.

A related monitor regression verifies that watch mode emits a timestamped
error sample and resumes after RPC unavailability. It never fills missing
samples with invented heights or counters. One-shot failures still exit nonzero,
and non-finite watch intervals are rejected before RPC. The executable fake-CLI
check fails with the previous monitor and passes after the change; evidence is
`mission/sync-watch-regression.json`.


Production subsequently demonstrated the bounded timeout without intervention.
Peer 39 owned requests 478544–478671 from 10:52:40 UTC, with an observed
10:57:40 deadline. The service journal records its automatic block-download
timeout at 10:57:40 under the same daemon PID, 503646. Subsequent RPC samples
show both global request counters and download-role counts at zero. The six
samples and journal records are retained in `mission/production-peer39-timeout-*`.
This verifies live request cleanup, not full synchronization: the active height
remains 478543 and no compatible healthy block source was available for takeover.


The corrected long stalled-peer comparison passed at all four limits. Each run
used a new datadir, reached height 4095 through normal validation, finished with
both global request counters at zero, and stopped through RPC with exit zero.
The fixture ends before the download-window boundary, so these cases exercise
the ordinary request timeout:

| Limit | A disconnected, seconds | Target reached, seconds | Peak RSS MiB | Abandoned/reassigned requests | Temporarily unavailable RPC samples |
|---|---:|---:|---:|---:|---:|
| 16 | 300.20 | 382.13 | 93.77 | 16 | 11 |
| 32 | 300.15 | 381.65 | 93.64 | 32 | 9 |
| 64 | 300.17 | 381.40 | 93.75 | 64 | 11 |
| 128 | 300.27 | 382.53 | 94.06 | 128 | 6 |

This is one long stalled run per limit. CPU time was 132.38–134.01 seconds,
with no swap or host CPU steal. Each received 36,657,388 P2P bytes, including
A's continuing headers. The duplicate request count equals the number of
abandoned A requests that B then served; no additional duplicates occurred.
All four reached a served-height gap of 4095 while the active tip waited for A.
Smaller limits reduce the number of requests to reassign but did not shorten
this timeout or materially change memory use in this workload. RPC sampling
delays during activation are retained in each result. Results and summaries
are in `mission/bench-4096-stalled-rpc-retry`, using daemon SHA256
`7ae6a707f53d52f9cc9899af938ff2364d8426f28aefcb08a0fc3d94f72f16b1`.


The controlled restart retained the active tip but reduced reported headers
from 542834 to 478543. Source inspection explains this through the existing
startup `RewindBlockIndex` routine: header-only entries outside the active chain
lack cached full-validation branch state, so it removes them and resets
`pindexBestHeader` to `chainActive.Tip()`. This is existing startup behavior,
not evidence of a new download-counter defect or failed database flush. The
mission has not changed that validation-related rewind logic. It is another
reason to avoid unnecessary production restarts while resolving the historical
block incompatibility.


All four larger-fixture runs passed through height 4608 and explicitly required
a logged download-window stall before the ordinary request deadline. The peer
disconnect time includes the time B needs to fill the window, followed by the
existing two-second stall interval:

| Limit | A disconnected, seconds | Target reached, seconds | Peak RSS MiB | Abandoned/reassigned requests |
|---|---:|---:|---:|---:|
| 16 | 43.59 | 141.09 | 95.24 | 16 |
| 32 | 27.69 | 123.94 | 95.40 | 32 |
| 64 | 22.45 | 117.93 | 95.30 | 64 |
| 128 | 21.09 | 116.78 | 95.77 | 128 |

All final global counters were zero, and every daemon stopped normally. These
fresh datadirs contain headers only through 4608, below the first non-genesis
checkpoint at 30000. `GetLastCheckpoint` therefore cannot select a checkpoint
above these downloaded blocks; their normal connection path retains expensive
proof and script checks. No shortcut was introduced for the benchmarks.

A transport-setting difference needs to be isolated before choosing a default
from these timings: the daemon sets `TCP_NODELAY` for outgoing and accepted
connections, while the Python fixture peers above did not set that option.
Their timings describe that recorded laboratory setup, including its TCP
behavior. The preserved harness is `mission/bench-window-nagle-harness.py`;
raw results and summaries are in `mission/bench-4609-window-stalled`. A comparison
with matching TCP settings follows before a final limit recommendation.

To run the benchmark harness against the included short fixture without mining:

```sh
python3 qa/rpc-tests/og-download-bench.py \
  --output /tmp/og-download-benchmark-new \
  --fixture src/test/data/zclassic-download-130.dat \
  --sha256 4ae8e7c4a2b2fb5b925ecc18752bf517dad39dd0a965a8c44d4fee29360ba2b6 \
  --tcp-nodelay
```

Use a newly named output directory and this branch's built daemon. `--stall`
enables a withholding peer; `--require-window-stall` additionally needs a fixture
through at least height 4097 and rejects recovery only through the ordinary
request timeout. Larger fixtures must be supplied with their SHA256. The
harness retains each datadir, logs, samples, binary/fixture/harness checksums,
RPC availability gaps, and final accounting assertions.


The matching-TCP window comparison also passed at every limit. All eight fixture
sockets reported `TCP_NODELAY` changing from 0 to 1. The setting changed measured
completion times by at most 1.3 seconds in these cases:

| Limit | A disconnected, seconds | Target reached, seconds | Peak RSS MiB |
|---|---:|---:|---:|
| 16 | 43.34 | 139.81 | 95.17 |
| 32 | 26.99 | 123.25 | 95.42 |
| 64 | 21.57 | 117.12 | 95.31 |
| 128 | 20.99 | 117.20 | 95.77 |

Every run reached 4608, released all requests, and stopped normally. The
limit-dependent window-fill time remained after matching TCP settings; it
cannot be attributed to the fixture's previous Nagle setting in this model.
The harness now exposes `--tcp-nodelay` and records actual socket option values.
Results are in `mission/bench-4609-window-nodelay`. The window-result check also
rejects incomplete peer reports or an ordinary request timeout, with a small
report-level check covering those failure cases.


Healthy downloads with matching TCP settings also pass at every limit, with
no RPC availability gaps, duplicate requests, or swap use. Completion times for
16/32/64/128 were 97.01/97.60/99.09/98.10 seconds, consistent with the earlier
three-run pipelined comparison. All sockets reported the requested option
value, all final request counters were zero, and all daemons stopped normally.
These confirmation results are in `mission/bench-4096-healthy-nodelay`.

The selected production default remains **128**. In the measured serial
service-delay workload it provided the best throughput; in the matching-TCP
window test it matched 64's recovery time. Peak RSS differed by about 1 MiB
across limits, and the ordinary stalled-peer deadline was the same. Smaller
limits reduced abandoned request counts and short sampled gaps behind the
active tip, but did not materially lower memory use or shorten the ordinary
timeout here. This is a conservative choice from the measured workloads,
not a claim that 128 is optimal on every connection or for later-chain blocks.
The bounded startup option remains available for operator-specific measurement.


The full ASan/UBSan daemon also passed the real outbound timeout regression,
with leak checking enabled: A disconnected after 300.115 seconds despite 11
header messages, B took over, and the same daemon validated through height 129.
RPC shutdown exited normally. Evidence: `mission/wire-asan-outbound`.

`qa/rpc-tests/og-peer-teardown.py` adds real socket teardown coverage while a
second thread reads peer, network, and chain RPCs. It alternates inbound and
outbound peers, each holding 128 requests, across FIN, TCP reset, and RPC
`disconnectnode`. Each cycle requires an empty peer list and zero global
request, validated-request, preferred-peer, and header-sync counters before
starting the next peer. A final healthy peer must normally validate blocks
through 129 without a daemon restart; mining stays disabled.

The normal daemon passed 48 cycles with 1,911 concurrent RPC calls. The full
ASan/UBSan daemon passed 96 cycles with 3,966 calls and leak checking enabled.
Every measured release completed within 0.51 seconds, including the fixture's
socket polling interval. Both runs recovered and exited normally with no peer,
RPC, or sanitizer errors. These checks exercise real thread lifetimes but are
not a data-race detector. Results: `mission/wire-teardown-normal-reset` and
`mission/wire-teardown-asan-reset`.

An initial sanitizer run exposed a fixture assumption: an intentional RPC
disconnect can result in a TCP reset rather than EOF. The harness now accepts
that reset only after requesting disconnect and records it; unexpected resets
remain errors. Two such reset closures occurred in the passing sanitizer run.
The original failed result is retained in `mission/wire-teardown-asan`.


A follow-up peer-list audit found that `getinfo` still read `vNodes.size()`
without `cs_vNodes`; its existing chain/wallet locks do not protect concurrent
socket removal or outbound insertion. That count now uses the peer-list lock,
matching `getnetworkinfo`. The teardown observer now includes `getinfo`.
The expanded test passed 48 normal cycles with 2,420 RPC calls and 96 sanitizer
cycles with 4,512 calls; both recovered to 129 and exited normally. The 37
relevant unit cases also passed normally and under ASan/UBSan with leak checking.
Evidence: `mission/wire-teardown-getinfo-{normal,asan}`,
`mission/getinfo-unit-tests.log`, and `mission/asan-framed-fuzz.log`.


The socket teardown harness now has `--malformed` coverage: a complete frame
with incorrect network magic triggers the message-handler disconnect, and a
24-byte header declaring 2 MiB + 1 byte triggers the receive-path protocol bound.
It sends no oversized payload and checks the corresponding log counts. With
both modes included in each connection direction, 50 normal cycles and 100
ASan/UBSan cycles passed, with 1,308 and 3,544 concurrent RPC calls respectively.
Both recovered to height 129 and stopped normally. Evidence:
`mission/wire-malformed-teardown-normal-size` and
`mission/wire-malformed-teardown-asan`.

The initial size declaration of 0xffffffff was safely rejected by the earlier
`MAX_SIZE` check, so the test's intended log assertion failed despite correct
cleanup. The corrected fixture targets the protocol bound specifically; the
initial result remains in `mission/wire-malformed-teardown-normal`.

ThreadSanitizer adds different coverage: the first instrumented run reported an
actual race between `ThreadSocketHandler` updating `nLastRecv` and `copyStats`
reading it for `getpeerinfo`. Its first-failure report is preserved in
`mission/wire-malformed-teardown-tsan`. This is separate from the original
in-flight accounting root cause, and the passing ASan runs do not disprove it.
The follow-up race fix and its validation are described below; these results do
not establish that the networking code is free of races.

### Peer-state concurrency follow-up

ThreadSanitizer subsequently reproduced races in the receive byte counter,
socket handle, handshake subversion string, and ping nonce/timestamps. The
candidate makes independently sampled I/O counters and timestamps atomic;
protects socket syscalls and close with one mutex; publishes version metadata
and preferred-download roles under `cs_main`; and protects ping state with
`cs_ping`. Protocol version is atomic for readers outside the chain lock.
Socket ownership remains private to `CNode`, and eviction compares captured
minimum-ping values so replies cannot change its ordering during a sort.

The socket mutex is released before attempting the receive-buffer lock during
disconnect. Ping sending releases its state mutex before queuing a message.
The extracted `MaybeSendPing` also reduces the branching in `SendMessages`.
Handshake parsing order, rejection conditions, block validation, and consensus
parameters are unchanged.

All 38 relevant unit cases passed normally and under ASan/UBSan with leak
checking, including a new test of queued ping nonce matching and elapsed-time
statistics. The matching ASan/UBSan daemon also passed real outbound recovery:
the stalled peer disconnected after 300.107 seconds despite 11 header messages,
the healthy peer validated through 129, and the daemon stopped normally.
Evidence: `mission/getinfo-unit-tests.log`, `mission/asan-framed-fuzz.log`, and
`mission/wire-peer-races-asan-outbound`.

The teardown observer's `--rpc-pings` option exercises ping requests concurrently
with RPC snapshots. With this option and malformed-frame coverage, the candidate
passed 50 normal cycles (575 RPC calls), 100 ASan/UBSan cycles (1,295 calls),
and 100 ThreadSanitizer cycles (1,715 calls). All reached height 129 without
restart, cleared download accounting, and exited normally. The TSAN run had no
warnings; ASan/UBSan ran with leak checking enabled. Evidence:
`mission/wire-malformed-peer-races-{normal,asan}` and
`mission/wire-malformed-tsan-ping-lock`.

`--shutdown-pending` instead leaves the final peer connected with all 128 block
requests outstanding and requires normal RPC shutdown. Ten-cycle ASan/UBSan
and TSAN runs passed, stopping in 0.823 and 0.323 seconds respectively. This
mode verifies shutdown, not chain recovery; the regular mode verifies recovery.
Evidence: `mission/wire-pending-stop-asan` and
`mission/wire-pending-stop-tsan-all`.

A separate TSAN report intermittently interrupts startup before any fixture
peer connects: libevent epoll descriptor handling overlaps a LevelDB directory
close. That report also reproduces in a small local libevent HTTP/directory-read
program without any Zclassic or LevelDB code. The ownership fix below addresses
this report without suppressions or event-backend changes. The failed runs
are retained in `mission/wire-malformed-tsan-handshake-lock` and
`mission/wire-pending-stop-tsan`; passing peer tests alone did not resolve it.

### HTTP socket ownership fix

Instrumenting the cached libevent source identified the exact startup sequence:
`evhttp_connection_free` closes the socket inside a write callback, which still
holds a buffered-event reference. Returning from that callback releases the
reference and removes its epoll registrations. Another thread can reuse the
descriptor before that removal; the directory-close report was one such overlap.

`CreateHTTPServer` now configures buffered events with `BEV_OPT_CLOSE_ON_FREE`.
The buffered event owns closure until its final reference releases the event
registrations. `InitHTTPServer` uses this factory. This applies the existing
library ownership API without patching dependencies, changing event backends,
or suppressing sanitizer findings.

The deterministic `httpserver_tests` case retains a buffered-event reference
across HTTP connection closure. It failed before the fix because the descriptor
was already closed, and passes afterward: the descriptor survives the retained
reference and closes when that reference is released. A second case verifies
keep-alive reuse followed by explicit connection closure. The tests use only
local ephemeral loopback sockets and the production server factory.

Relevant normal unit suites and both HTTP cases passed. All 40 relevant
ASan/UBSan unit cases passed with leak checking in 73.083 seconds. The actual
TSAN daemon passed startup, 100 teardown cycles, 2,465 concurrent RPC calls,
recovery through height 129, and normal shutdown with no warnings. The ASan/UBSan
daemon passed 50 cycles and 1,000 RPC calls, then stopped with 128 requests still
pending in 0.818 seconds. Evidence: `mission/http-lifetime-before.log`,
`mission/http-unit-after*`, `mission/http-unit-keepalive*`,
`mission/http-asan-unit*`, and `mission/wire-http-ownership-{tsan,asan}`.

### Eviction with pending requests

The teardown harness now supports `--eviction`: it fills 16 inbound slots,
queues concurrent RPC pings, and replaces one peer at a time. The test sets
`maxconnections=32` because this Zclassic source reserves 16 outbound slots.
After each replacement it requires exactly 16 ready inbound peers, exactly one
departing and one arriving peer, unique assignments for fixture blocks 1–129,
and matching global actual/validated request counts. It then clears the peers,
checks zero accounting, and validates through height 129 with a healthy peer.

The normal candidate passed 24 replacements; ASan/UBSan and TSAN each passed
64, with normal shutdown and no sanitizer findings. The runs observed 128,
2, and 385 abandoned requests being reassigned respectively; the exact victims
depend on ping measurements and connection timing. Maximum sampled replacement
times were 0.120, 0.144, and 0.153 seconds, including polling/RPC overhead.
Evidence: `mission/wire-eviction-normal-cap32`, `mission/wire-eviction-asan`, and
`mission/wire-eviction-tsan`. An initial fixture using a total limit of 24 failed
because it supplied only eight inbound slots; its normal-exit result is retained
in `mission/wire-eviction-normal`.
