# C++ node networking coordination

## Hetzner baseline — 2026-09-26

The authorized checkout is `/opt/zclassic-money`, the C++ Zclassic node.
Branch `agent/hetzner-networking-20260926` starts at
`28971f6154de6b91bd842357e53675d17addbc77`, preserving the complete history of
`fix/timeout-overflow-20260916`. The C23 checkout is outside this assignment.

Two inherited commits are ahead of the old branch's tracking ref:

- `5f7c0d59ba974e92d6add40428973b1803799b8f`: receive queue accounting uses
  saturating `size_t` arithmetic and tests message overhead.
- `28971f6154de6b91bd842357e53675d17addbc77`: miner thread requests are bounded
  by available cores, with deterministic boundary coverage.

Fetching the publication remote showed both commits already exist on separate
fix branches. They are preserved unchanged, not new networking work.

The initial tracked working tree and index were clean. The untracked `mission/`
tree occupied 3.8 GiB, with 585 top-level regular files and 156 immediate
subdirectories (including the root in that count). It contains prior fixtures,
measurement reports, build outputs and preserved sanitizer/source worktrees.
It remains untouched and excluded from commits. The existing stash of unfinished
misbehavior work also remains untouched. No running daemon or compiler was found
in the initial process inspection; no service or canonical datadir is modified.

## Ownership

Hetzner owns IBD networking, peer scheduling, timeout/disconnect recovery,
headers/blocks flow, adversarial-network handling and node observability.
Worldstream owns storage, pruning, database, restart performance and resource
efficiency. Its fetched `dev/ibd-performance-20260918` head is
`3b9205df010b98153497934c2cfaebf940246c27` (live-prune documentation).
No Worldstream source is being duplicated or merged into this networking slice.

Only this development branch may be pushed. Consensus predicates, PoW,
monetary policy, transaction validity, upgrade behavior and chain history remain
unchanged. Tests use local isolated fixtures; raw mission evidence, datadirs,
wallets, credentials, logs and build artifacts are never staged.

## Invalid foreign block replies and request ownership

The C++ scheduler already bounds one peer to 128 requests against a 4,096-block
window. Existing timeout/disconnect tests establish immediate release before the
last peer reference is destroyed. Inspection instead found a request-ownership
violation in the preliminary block-rejection path.

Before the fix, a second peer could send the valid header of an assigned block
with a mismatching transaction body. `CheckBlock` correctly rejected the body,
but `ProcessNewBlock` still removed the first peer's matching request. The
production-message regression measured 128 requests becoming 127, an oldest
request deadline changing from 300 to 375 seconds, and changed request order.
Five assertions failed. The invalid-owner control already passed.

Request removal now optionally checks the recorded owner under `cs_main`.
Preliminary-invalid network replies use that restriction. Valid cross-peer
replies, invalid owner replies, local processing, forced processing, and normal
timeout/disconnect cleanup retain their existing behavior. No block-checking,
acceptance, PoW, transaction, monetary, upgrade, or serialization rule changed.
This claim concerns preliminary-invalid replies; later contextual or storage
rejections retain their existing behavior.

After the fix, both ownership cases pass (1,090 assertions). The healthy owner's
128 requests and original deadline remain unchanged after the foreign invalid
reply. The owner-invalid case releases the missing block and a healthy peer
claims it on its next send tick at the same simulated timestamp. Valid foreign
delivery still advances the fixture chain. All 42 download cases pass, including
64,678 assertions, held-reference cleanup, randomized reassignment, malformed
framing, header progress and import-pause recovery.

The separate candidate daemon reaches `Done loading` in an isolated regtest
fixture with wallet, external connections and bootstrap disabled, then exits 0
after SIGTERM. Binary inspection reports full RELRO, stack canary, NX, PIE, and
no RPATH/RUNPATH. The source change has an independent ownership/locking and
consensus-scope review. Broad and sanitizer results are recorded below when
complete; no mainnet IBD throughput or production deployment is claimed.

Next: reproduce header-source failover under civil-clock corrections before
changing its timer. Public RPC epoch fields must retain their meaning.

Final validation for this slice:

- Full rebuilt Boost suite: 481/481 cases, 143,426,512 assertions, 520.56 seconds.
  This includes PoW, Equihash, subsidy, block, transaction and script checks.
- GoogleTest `UpgradesTest.*`: 6/6 activation/epoch cases.
- ASan/UBSan with leak detection: 2/2 ownership cases in 5.52 seconds and all
  42 download cases in 206.77 seconds, with no sanitizer findings. Only
  `main.cpp` and `block_download_tests.cpp` were instrumented; remaining objects
  and dependencies used the normal build. Whole-program coverage is not claimed.
- Whitespace/diff checks and independent source review passed. No validation
  predicate, threshold, timeout constant or assertion was weakened.

The measured source is base `28971f6154de6b91bd842357e53675d17addbc77`
plus the two-file source/test patch with SHA256
`f3127f010321efd5ff2ae614a9be16fe4b737d138eda9b69c9eb91051c1554b2`.
Raw evidence and candidate binaries remain outside Git. These fixture checks do
not establish fresh mainnet sync, sustained peer diversity, or historical-chain
acceptance; those remain separate observations.

## Header-sync expiry under civil-clock corrections

A deterministic two-clock regression reproduced seven failures in the former
wall-time header timeout. A backward wall step retained the expired source's
header role and prevented the healthy source from issuing `getheaders`; a
forward step disconnected the source before its elapsed 900-second allowance.
The test varies wall time by plus/minus 3,600 seconds while independently
advancing elapsed time through 899 seconds, 900 seconds and 900 seconds + 1 us.

Header deadline creation, verified-progress refresh and expiry now share a
process-local monotonic clock. Its origin makes values nonnegative, zero remains
reserved, and test overrides are independent of the wall clock. The allowance
remains 15 minutes with the same strict greater-than expiry boundary. Role
cleanup, preferred-source priority and import-pause handling are unchanged.

`getpeerinfo` retains its existing epoch `header_sync_deadline`, projected from
current wall time plus the monotonic remainder with saturation at `INT64_MAX`.
`header_sync_timeout_remaining` comes directly from that remainder. The RPC
regression covers both civil-time directions and epoch saturation while retaining
a 900-second remainder. Expired but not yet cleaned-up roles project to the
observation time and report zero remaining; the scheduler still owns cleanup.

The final focused suite passes 44 cases and 65,787 assertions in 51.62 seconds.
It covers exact expiry, immediate healthy-source takeover, genuine header
progress, repeated batches, import/reset lifecycle and the previous ownership
regressions. Independent source review found no blocking issue. Broader results
are recorded below when complete.

Scope: header scheduling and its diagnostics only. Block-request, ping, socket,
and consensus wall clocks remain unchanged. This does not establish whole-node
clock-jump resilience, native non-Linux acceptance, or public-network IBD rates.
No validation predicate, PoW, monetary, transaction or upgrade rule changed.
The next networking slice is inventory send-buffer refusal: reproduce whether
newly reserved but unsent requests prevent immediate reassignment, preserving
previously issued requests and their stall age.

Final validation for the header-clock slice:

- Full rebuilt Boost suite: 483/483 cases, 143,037,029 assertions, 468.55 seconds.
- GoogleTest upgrade activation/epoch checks: 6/6.
- Selective ASan/UBSan with leak detection: both clock cases, the RPC diagnostic
  case, and all 44 download cases pass; full download run 152.23 seconds with no
  findings. All four changed translation units (`main.cpp`, `utiltime.cpp`,
  `rpc/net.cpp`, and the download tests) were instrumented; other dependencies
  and objects were not.
- The separate daemon passes isolated regtest startup and SIGTERM shutdown
  (exit 0), plus full RELRO, canary, NX, PIE and no-RPATH/RUNPATH inspection.
- Diff checks and independent review pass. The exact source is
  `0282a7637ee0c747724e228d07ca34acb9a36e1b` plus source/test patch SHA256
  `9ee0fc9169fb5ab50550be29ca966351b23352217643409fd8982df3593a0939`.

## Malformed block ingress releases swarm reservations

A validly framed but truncated `block` payload reached the native message
parser, generated a malformed reject, and left the connection alive. A peer
which owned the normal 128-block IBD batch could therefore retain all of its
reservations until the ordinary block timeout despite having supplied no usable
response. The existing fragmented-frame test only demonstrated recovery after
an explicit simulated remote close, so it did not cover this wire-level path.

`ProcessMessages` now marks a peer for ordinary disconnect when deserializing a
complete `block` or `headers` payload raises an I/O parse failure. It assigns no
ban score and does not alter validation; the established disconnect path drops
only that peer's request ownership and permits another source to claim the
work. The focused framed-ingress regression supplies a checksum-valid one-byte
`block` frame, proves 128 reservations are cleared, and proves a healthy peer
claims the batch and advances the fixture through height 129.

The complete `block_download_tests` group passes 46 cases, including malformed
framing, randomized reassignment, timeout, disconnect and header-source
failover coverage. The affected normal C++ objects rebuilt incrementally with
the existing tree. No reusable sanitizer binary is present; with 13 GB free
and a required 10 GB reserve, a cold sanitizer build was not started. No C23,
storage, consensus, PoW, monetary, transaction, serialization, upgrade, wallet
or production-datadir surface is involved. Worldstream's storage/startup scope
is not modified. A follow-up read-only transport-loop trace found no extra
scheduler interval: `ThreadMessageHandler` calls `SendMessages` after
`ProcessMessages` in the same peer iteration, and its existing
`fDisconnect` branch calls `StopBlockDownload`; `ThreadSocketHandler` then
performs idempotent removal. Remaining risk is ordinary lock contention before
that same-iteration send pass, not retained ownership across a later polling
cycle. The next networking investigation should target a distinct measured
source-diversity or header-gap condition rather than duplicate this lifecycle.

## Disconnect gate precedes bootstrap serving

The native message handler calls `SendMessages` for a peer in the same
iteration in which malformed ingress can mark it disconnected. Before this
slice, `SendMessages` invoked ping handling and
`SendQueuedBootstrapSnapshotChunk` before its later `fDisconnect` cleanup.
Thus a peer with queued snapshot work could consume a snapshot read and send
buffer allocation after it had already been selected for teardown. This was a
bounded but avoidable resource path, independent of snapshot validity.

The disconnect gate now runs immediately after the version gate. It performs
the existing idempotent block-download release when `cs_main` is available and
returns before ping or bootstrap serving. A deterministic protocol regression
queues a snapshot request on a disconnected, versioned peer, runs
`SendMessages`, and proves the request remains queued for teardown rather than
being popped for service. It proves no consensus or bootstrap acceptance rule;
manifest and chunk validation are unchanged.

The focused regression passes 7 assertions. The complete
`bootstrap_snapshot_protocol_tests` group passes 56 cases, and the complete
`block_download_tests` group passes 46 cases after the same incremental native
rebuild. Worldstream's latest accessible `agent/worldstream-ibd-20260918`
head is `d9f5153be8fc59d140db9b6f59e796a7c668160a`; it changes C23
coins-tip restart recovery only, so there is no overlap. Consensus impact:
NONE. With 13 GB free and a mandatory 10 GB reserve, no cold sanitizer build
was started and no sanitizer result is claimed. Next investigate a distinct
peer-source diversity condition in the C++ bootstrap driver or block scheduler.

## Truncated headers release their discovery role

The malformed-ingress disconnect rule applies to both `block` and `headers`,
but the original wire-level regression covered only a truncated block body.
The new headers case uses a checksum-valid complete frame that declares one
header and supplies no header bytes. It proves the parser marks the peer for
disconnect, `SendMessages` clears its active header role, and a healthy
outbound peer immediately sends `getheaders` and claims its normal block
batch. An empty headers reply remains distinct and valid; the test deliberately
uses a nonzero count to exercise deserialization failure.

Both direct framed regressions pass (670 and 544 assertions respectively), and
the complete `block_download_tests` group passes 47 cases. This is protocol
recovery coverage only: no header, block, checkpoint, PoW, chain-selection or
validation rule changed. Consensus impact: NONE. No sanitizer run is claimed;
the existing 13 GB free-space headroom is reserved against a cold sanitizer
build. The next investigation remains bootstrap-client source diversity or a
distinct scheduler condition.

## Bootstrap throttle requeue preserves the deferred request

The per-peer bootstrap serve queue previously admitted requests up to all 32
slots. If the serving thread popped an older request, then a message thread
filled that freed slot before a throttle decision requeued it, the requeue was
silently dropped. The client eventually retried, but a bounded, healthy request
could lose FIFO service and wait for a timeout under reconnect/queue churn.

Admission now reserves one of the existing 32 bounded slots for a possible
in-flight requeue. Normal queued depth is 31; a throttle requeue restores the
older request at the front to reach the unchanged hard cap of 32. The
deterministic regression fills admission, pops one request, refills the freed
slot as a concurrent message would, requeues the deferred request, and proves
that request is served first while further admission is still refused at the
cap.

The focused regression passes 9 assertions and all 57
`bootstrap_snapshot_protocol_tests` cases pass. No snapshot acceptance,
manifest/chunk verification, chain validation, consensus rule, or resource cap
is weakened. Consensus impact: NONE. Worldstream remains confined to C23
storage/restart work. With 13 GB free space, no cold sanitizer build was run;
this incremental native build used existing artifacts. Next investigate a
distinct client-side source-diversity or ordinary block-scheduler condition.

## Exact duplicate bootstrap peers no longer consume failover budget

Bootstrap peer selection retries each configured source before proceeding to the
next one. Previously, repeated identical `-bootstrappeer` entries were treated
as separate sources, so one unreachable endpoint could consume the full retry
budget repeatedly before a distinct configured peer was tried. This reduced
the intended source diversity without adding any independent availability.

`GetBootstrapPeerList` now removes only exact duplicate endpoint strings while
preserving first-seen order and the existing explicit-peer precedence. The
same normalization protects compiled defaults if an accidental duplicate is
introduced. It does not resolve aliases or infer trust/network identity, and
does not alter manifest, snapshot, block or consensus validation.

The peer-list regression now supplies repeated explicit endpoints and proves
the ordered distinct list; it also derives and checks the normalized compiled
defaults. All 57 `bootstrap_snapshot_protocol_tests` cases pass after the
incremental native rebuild. Consensus impact: NONE. Worldstream remains on
separate C23 storage/restart work; no sanitizer run is claimed while retaining
13 GB free-space headroom. Next investigate an ordinary block-scheduler or
bootstrap-client failure mode that has a bounded local reproduction.

## Malformed notfound cannot release owned blocks

`notfound` replies are an immediate availability signal: a well-formed reply
for an owned block disconnects that source and releases its batch for another
peer. Before this slice the handler decoded the declared inventory but ignored
remaining payload bytes, so an owned-block reply with trailing garbage could
trigger that release before the malformed wire message was rejected.

The handler now requires the declared inventory to consume the complete
payload before changing ownership. Trailing bytes score the sender and return
an error with no disconnect or request mutation. The regression starts with a
128-block assignment, sends an owned `notfound` plus one trailing byte, and
proves the assignment and global validated count remain unchanged while
misbehavior rises by at least 20.

The focused case passes 541 assertions and the full `block_download_tests`
group passes 47 cases. No availability behavior changes for well-formed
`notfound` responses, and no block/header/consensus validation predicate is
changed. Consensus impact: NONE. Worldstream remains separate C23
storage/restart work. No sanitizer result is claimed; the incremental normal
build fits within the preserved 13 GB free-space headroom. Next target a
distinct peer-scheduler or bootstrap-client recovery condition.

## Trailing headers payloads cannot publish peer availability

The native `headers` handler decoded the declared header count but did not
require the payload to be exhausted before applying header-derived peer state.
A peer could append bytes after a syntactically valid header response and have
its availability updated before the message was rejected elsewhere, making
malformed traffic appear to be usable IBD progress.

The handler now rejects remaining bytes immediately after decoding the declared
headers and their required zero transaction counts. It assigns the existing
malformed-message score and returns before taking `cs_main` or updating header
availability, block requests, or peer progress. A deterministic regression
sends one valid header followed by a byte of trailing data, proves peer sync
height and in-flight accounting do not change, then proves a following valid
response advances the peer normally.

The focused regression passes 531 assertions. The complete
`block_download_tests` group passes 48 cases and 68,218 assertions after an
incremental native rebuild. Consensus impact: NONE: no header/block acceptance,
PoW, chain selection, transaction, serialization, monetary, or upgrade rule
changed. Worldstream's latest accessible C23 head remains
`d9f5153be8fc59d140db9b6f59e796a7c668160a` and has no overlapping C++
networking change. With 13 GB free and a 10 GB reserve, no cold sanitizer build
was started. Next investigate a distinct bootstrap-client source-diversity or
ordinary block-scheduler recovery condition.

## Headers require their mandated zero transaction counts

Each serialized header in a `headers` message is followed by a CompactSize
transaction count which the protocol requires to be zero. The handler decoded
that value but discarded it, so a sender could set it nonzero and still cause
the declared header to update peer availability. A new regression established
the baseline: count `1` returned success, changed sync height from `-1` to `1`,
and assigned no misbehavior.

The handler now rejects a nonzero count with the existing malformed-message
score before acquiring `cs_main` or changing peer/header/block scheduling
state. The direct regression confirms no peer progress or in-flight accounting
changes. The adjacent trailing-payload regression remains green, proving the
two malformed encodings are handled independently.

The two focused cases pass with 531 and 528 assertions respectively; the full
`block_download_tests` group passes 49 cases and 68,746 assertions. Consensus
impact: NONE. Header/block acceptance, PoW, chain selection, transaction,
serialization, monetary, and upgrade rules remain unchanged. Worldstream's
latest accessible C23 head remains storage/restart-only and does not overlap.
No cold sanitizer build was started with 13 GB free and the 10 GB reserve.
Next investigate a distinct bounded bootstrap-client or block-scheduler
recovery condition.

## Trailing inventory payloads cannot schedule downloads

The `inv` handler deserialized its declared inventory vector but accepted
trailing bytes, then updated block availability and emitted `getheaders` before
any malformed-message rejection. A focused baseline sent one valid block
inventory plus a byte and reproduced success plus a scheduled `getheaders`.

The handler now requires complete payload consumption before acquiring
`cs_main` or touching availability, requests, or inventory state. The direct
regression proves malformed inventory neither emits `getheaders`/`getdata` nor
changes local/global in-flight accounting, and assigns the existing score.

The focused case passes 530 assertions; all 50 `block_download_tests` cases
pass with 69,276 assertions. Consensus impact: NONE. No block, transaction,
PoW, chain-selection, serialization, monetary, or upgrade rule changed.
Worldstream remains non-overlapping storage/restart work. No cold sanitizer
build was run with 13 GB free and the 10 GB reserve.

## Trailing getdata payloads are rejected before service

The `getdata` handler accepted trailing bytes after a declared inventory list.
A bounded regression established that malformed input returned success without
the standard malformed-message score. The handler now requires payload
exhaustion before logging, queuing service work, or calling `ProcessGetData`.

The focused regression passes 527 assertions; all 51 `block_download_tests`
cases pass with 69,803 assertions. Consensus impact: NONE. No validation,
PoW, chain selection, serialization, monetary, or upgrade rule changed.
Worldstream remains non-overlapping and no cold sanitizer build was started
within the preserved 13 GB free-space headroom.
