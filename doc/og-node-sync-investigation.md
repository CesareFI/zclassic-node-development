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
is limited to the code built with sanitizer instrumentation.

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
preliminary failure is before full contextual/UTXO validation, so the block's
complete validity has not yet been established by this node.

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
contextual or proof validity.

## Hypothesis status

| Hypothesis | Evidence/status |
|---|---|
| A stalled peer keeps all 128 requests indefinitely | Hours-long retention proven; deadline is finite (53 hours), not literally infinite. |
| Teardown leaks global request accounting | Proven in source, live memory, and deterministic regression. |
| Stale accounting inflates future timeouts | Proven in source and regression; live inflated counter and deadline captured. |
| Headers hide lack of block progress | Headers continue without progress; they do not directly reset the block deadline. |
| Abandoned requests are not immediately reassigned | Previously retained until finalization; timeout cleanup and B takeover tested. |
| No usable outbound peers during IBD | Zero outbound captured; reachable seed peers are banned; semaphore exhaustion ruled out. |
| Block 478544 fails normal validation | Exact current rejection is `bad-txns-oversize`; full historical-rule validation remains outstanding. |
| Sapling/Overwinter compatibility involved | Post-Sapling size bound is involved; no evidence yet of proof or branch-ID failure. |

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

The production node is not fixed yet. Historical compatibility and full block
validation, continued production progress past the next 128-block boundary,
sustained useful outbound connections, sanitizers, and the 16/32/64/128 performance
comparison are still required. No chainstate or block files have been deleted.

## Additional peer lifetime safety

The `setban` RPC previously repeatedly looked up the first matching peer until
the socket thread removed it. It also used that borrowed pointer outside the
peer-list lock. The corrected traversal holds the lock and marks every matching
peer once. `disconnectnode` now holds the same lock from lookup through use,
and `ConnectNode` holds it while finding an existing peer and acquiring its
reference. These changes do not alter consensus or ban policy.

A regression keeps connected peer objects alive and listed while invoking the
RPC. Before the traversal fix it timed out after 20 seconds; afterwards it
returns and flags both matching peers while leaving an unrelated peer connected.
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
those values unknown instead of assuming zero.
