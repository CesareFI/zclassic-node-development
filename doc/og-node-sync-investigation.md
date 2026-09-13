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
limit comparison. The short harness test passes at all four limits. Quiet-host
measurements and stalled-peer comparisons remain outstanding; no performance
claim or default change is justified yet.

A package installation caused `needrestart` to restart production automatically
at 07:08 UTC. The unit stopped through RPC, logged shutdown completion, and
systemd reported success; mining remained off. It loaded the already tested
limit-option build, SHA256
`84732b84c233277dd2a16aea5674dab0ce2c08aa6e331c1f99442035c82d67b9`.
Subsequent package installations must set `NEEDRESTART_MODE=l` to prevent
unplanned restarts. The latest socket lifecycle and outbound ownership changes
have not yet been deliberately deployed to production.
