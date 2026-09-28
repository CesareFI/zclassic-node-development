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

## Trailing chain requests cannot enter service

Baseline and root cause: `getblocks` and `getheaders` decoded their required
locator and stop hash, but did not require the payload to end before taking
`cs_main` and entering their serving paths. A bounded direct regression sent a
valid empty locator and stop hash followed by one byte. Both commands returned
success and assigned no malformed-message score (four deterministic assertion
failures), proving that a malformed request could reach service selection.

Fix and after-result: each handler now requires the locator payload to be
fully consumed immediately after decoding and before taking `cs_main`. A
trailing byte receives the existing score of 20 and returns an error. The
regression verifies both commands emit neither inventory nor headers and leave
per-peer/global block-in-flight accounting unchanged.

Regression proof: the focused direct case passes after an incremental native
rebuild. The full `block_download_tests` suite passes all 52 cases (`*** No
errors detected`). `git diff --check` passes. The legacy checkout has no
cyclomatic-complexity gate; no sanitizer run is claimed because only 11 GB
remain with a 10 GB reserve and a cold sanitizer build would not fit safely.

Consensus impact: NONE. This rejects malformed P2P framing before ordinary
serving; block/header acceptance, PoW, chain selection, serialization,
transaction validity, monetary rules, upgrades, and cryptography are
unchanged. Worldstream's accessible work remains C23 startup/fresh-sync only.
Remaining risk: audit the next distinct bounded P2P message path rather than
changing scheduling policy without a measured stall.

## Block deadlines ignore civil-clock jumps

Baseline and root cause: header discovery already used a monotonic deadline,
but block-request deadlines and the block-window stall timer used
`GetTimeMicros()`. A bounded two-case regression held monotonic elapsed time
one microsecond before a real request deadline while moving civil time by
minus or plus one hour. The pre-fix code produced five assertion failures: a
forward wall-clock correction could disconnect a healthy block source before
its elapsed timeout.

Fix and after-result: block request timestamps, request deadlines, and stall
starts now use `GetSteadyTimeMicros()` exclusively for scheduling. Public
`getpeerinfo` state still reports epoch-based request times and deadlines by
projecting the monotonic remaining duration onto the current wall clock; those
estimates are diagnostics only and cannot drive a disconnect. The regression
proves both clock directions preserve the source until the strict monotonic
deadline, then disconnect and release its in-flight request after it.

Regression proof: the focused two-case request-deadline test passes after the
native incremental rebuild. A separate two-case full-window fixture builds
only 4,097 in-memory index entries (no block bodies, PoW, validation, or chain
activation), fills the real 4,096-block scheduler window, and proves the
recorded staller also ignores both civil-clock directions until its strict
monotonic timeout. The complete `block_download_tests` suite is rerun after
that coverage. `git diff --check` passes. No cold sanitizer build was started:
11 GB free remains above the 10 GB reserve but is not enough for a safe cold
sanitizer profile; this legacy tree has no cyclomatic-complexity gate.

Consensus impact: NONE. This is local operational timeout accounting only;
block/header validation, PoW, chain selection, serialization, transaction
rules, monetary policy, upgrade activation, and cryptography are unchanged.
Worldstream remains non-overlapping C23 startup/fresh-sync work. Remaining
risk: exercise a distinct bounded block-window stall scenario before changing
peer-selection policy.

## Malformed address advertisements cannot enter discovery

Baseline and root cause: the `addr` handler decoded its declared address
vector but accepted trailing bytes, then relayed and stored advertised peers.
A direct fixture sent one valid routable address followed by one byte and
reproduced success, addrman mutation, and no malformed-message score.

Fix: require the address vector to consume the complete payload before any
relay or addrman mutation. Trailing bytes now receive the existing score of
20 and return an error. The regression proves the address count is unchanged.

Consensus impact: NONE. This is P2P peer-discovery framing only; validation,
PoW, chain selection, serialization, monetary policy, upgrades, and
cryptography are untouched. Worldstream remains non-overlapping C23
startup/fresh-sync work.

## Bootstrap discovery rejects trailing address payloads

Baseline and root cause: the normal P2P `addr` path had already been made
strict, but the bounded bootstrap discovery client has its own socket and
deserializer. It accepted a valid advertised `NODE_BOOTSTRAP` address vector
followed by arbitrary bytes, allowing malformed untrusted discovery traffic to
become a bootstrap source. This is not a consensus shortcut, but it weakens
the discovery client's framing boundary and makes malformed source selection
harder to diagnose.

Fix and after-result: `DecodeBootstrapDiscoveryAddresses` now decodes the
entire wire payload before it changes the caller's discovered-peer vector. A
trailing byte, malformed vector, or over-limit vector leaves the result and
appended-count untouched; valid, unique `NODE_BOOTSTRAP` addresses retain the
same bounded acceptance behavior. The socket handshake, candidates, timeout,
and compiled-anchor verification remain unchanged.

Regression proof: the deterministic payload fixture serializes an authentic
`addr` vector plus one byte and proves rejection with no source-list mutation;
its companion validates acceptance of one unique bootstrap address while
filtering a duplicate and a non-bootstrap service. Both focused cases pass,
the 59-case `bootstrap_snapshot_protocol_tests` suite passes after an
incremental C++ rebuild, and all 57 `block_download_tests` cases pass. `git
diff --check` passes. No ASan/UBSan result is claimed: 11 GB free preserves
the required 10 GB reserve, but does not safely accommodate a cold sanitizer
profile. This legacy C++ checkout has no cyclomatic-complexity gate.

Consensus impact: NONE. The change only rejects malformed optional discovery
framing before source selection; chain history, block/header and transaction
validation, PoW, serialization, monetary policy, upgrades, and cryptography
are untouched. Worldstream's latest accessible C23 head
`d9f5153be8fc59d140db9b6f59e796a7c668160a` remains storage/restart-only, so
there is no overlap. Remaining risk: inspect a distinct bootstrap
manifest-source diversity/reconnect condition rather than broaden scheduler
policy without a measured failure.

## Bootstrap retry rounds preserve source diversity

Baseline and root cause: a fresh node with several configured bootstrap
sources tried source A three times before source B once. A reconnecting or
slow A could consume two full bootstrap timeout windows after its first
failure, delaying a healthy B and making a multi-source configuration behave
like a single-source configuration during the most failure-prone startup
period.

Fix and after-result: the bounded retry budget is unchanged (three attempts
per source), but `BootstrapPeerRetrySchedule` emits attempt one for every
source before attempt two for any source. The 3-second backoff is now between
failed rounds, never between distinct sources; a healthy B receives its first
attempt immediately after failed A. One configured peer retains exactly the
previous retry and backoff behavior. Each failed attempt still uses the
existing self-contained staging cleanup, and no peer is trusted beyond the
unchanged manifest and imported-state checks.

Regression proof: the deterministic scheduler regression proves the exact
three-source sequence A1, B1, C1, A2, B2, C2, A3, B3, C3 and refuses empty or
zero-budget schedules. It passes together with all 60
`bootstrap_snapshot_protocol_tests` cases and all 57 `block_download_tests`
cases after an incremental C++ rebuild. The make-driven broad legacy suite
also reported 327 failures in unrelated `rpc_wallet_tests`: concurrent/global
ECC context initialization trips `ECC_Start()`'s existing assertion. That
failure is recorded as failed and unrun for this networking slice; it is not
masked or attributed to this change. `git diff --check` passes. ASan/UBSan is
unrun because 11 GB free preserves the 10 GB reserve but cannot safely hold a
cold sanitizer build; this legacy checkout has no cyclomatic-complexity gate.

Consensus impact: NONE. Only local bootstrap attempt order and backoff timing
change; chain history, peer wire compatibility, imported snapshot validation,
block/header and transaction validation, PoW, serialization, monetary policy,
upgrades, and cryptography are untouched. Worldstream's accessible C23 head
`d9f5153be8fc59d140db9b6f59e796a7c668160a` is storage/restart-only and does
not overlap. Remaining risk: establish whether parallel snapshot streams can
recover individual transient stream failures without discarding verified
staging, before considering any broader source-mixing policy.

## Bootstrap manifest streams require exact payloads

Baseline and root cause: bootstrap snapshot acquisition has a separate socket
path from normal `CNode` message processing. Its master-manifest connection,
parallel reconnect streams, and Zcash-parameter manifest client deserialized a
manifest but accepted remaining bytes. Thus a source could present a valid
manifest followed by arbitrary wire data and still enter manifest validation or
the parallel-stream identity comparison.

Fix and after-result: all three clients now share
`DecodeBootstrapSnapshotManifestPayload`. It decodes into a temporary,
requires payload exhaustion, and assigns the caller's manifest only on exact
success. A malformed payload therefore cannot alter an already-held master
manifest or start staging work; valid serializations and the existing
manifest/anchor/hash checks are unchanged.

Regression proof: a deterministic wire fixture proves a valid manifest
round-trips with complete consumption, then appends one byte and proves
rejection while preserving the caller's prior v3 manifest. The focused case
and the complete 61-case `bootstrap_snapshot_protocol_tests` group pass after
an incremental C++ rebuild. `git diff --check` passes. ASan/UBSan remains
unrun because 11 GB free must retain the 10 GB reserve and cannot safely hold
a cold sanitizer build; this legacy checkout has no cyclomatic-complexity
gate. The known unrelated broad `rpc_wallet_tests` ECC-context collision from
the previous slice remains failed/unaddressed, not suppressed.

Consensus impact: NONE. This is strict handling of optional bootstrap and
parameter transfer framing before existing validation; chain history,
consensus serialization, PoW, monetary policy, upgrades, block/transaction
validation, and cryptography are untouched. Worldstream remains non-overlap
storage/restart work at `d9f5153be8fc59d140db9b6f59e796a7c668160a`.
Remaining risk: a full isolated reconnect fixture is still needed before
changing parallel-stream retry/resume behavior.

## Bootstrap chunk delivery rejects malformed residual data

Baseline and root cause: the normal `CNode` unsolicited `BSCHK`/`BSPCHK`
handler already checked residual bytes, but the standalone snapshot and Zcash
parameter download sockets each deserialized a chunk then immediately advanced
their in-flight request and file-write path. A valid chunk followed by residual
wire data was therefore accepted on the actual bootstrap transfer path.

Fix and after-result: both clients now use
`DecodeBootstrapSnapshotChunkPayload`, which decodes into a temporary and
requires exact consumption before assigning the output chunk. Decode,
truncation, or trailing-byte failure leaves the caller's prior chunk untouched,
so neither the request queue nor any staging write is reached. Normal P2P
chunk scoring and wire behavior are intentionally unchanged.

Regression proof: the direct wire fixture proves valid chunk decoding, then
tests a trailing byte and a truncated serialization. Both failures preserve a
sentinel chunk's file index, offset, and data. The focused case and complete
62-case `bootstrap_snapshot_protocol_tests` group pass after an incremental
C++ rebuild. `git diff --check` passes. ASan/UBSan remains unrun because 11 GB
free preserves the required 10 GB reserve but cannot safely accommodate a cold
sanitizer build; no legacy cyclomatic-complexity gate exists. The previously
observed unrelated broad RPC-wallet ECC-context failure is not masked.

Consensus impact: NONE. This rejects malformed optional transfer framing before
the existing chunk size, offset, per-file hash, manifest, and imported-state
checks. Chain history, consensus serialization, PoW, monetary policy, network
upgrades, block/transaction validation, and cryptography are untouched.
Worldstream remains non-overlap storage/restart work at
`d9f5153be8fc59d140db9b6f59e796a7c668160a`. Remaining risk: bounded
localhost reconnect coverage is still prerequisite evidence for safely adding
parallel-stream retry/resume behavior.

### CI checkpoint

GitHub Actions run
[`36346553038`](https://github.com/CesareFI/zclassic-node-development/actions/runs/36346553038)
completed successfully for `fc130ea1383db94f8236f4364e0b29b4cd9dbf38` on
2026-09-27. It passed dependency cache restore, `Build depends`, CCache,
`Build Zclassic`, and artifact upload. In particular, the native_ccache 3.3.1
official-release download and its unchanged pinned SHA-256 verification no
longer fail in the previously affected CI stage. This build result does not
replace the focused C++ test results above and does not claim sanitizer
coverage.

## Loopback reconnect-stream manifest fixture

Baseline and root cause: the parallel snapshot reconnect path opens a new
socket, repeats the bootstrap handshake, and must prove that its manifest is
identical to the already accepted master manifest. The existing unit tests
covered serialization helpers but had no native loopback peer exercising the
actual TCP handshake and reconnect-stream verifier, leaving source-divergence
and malformed-response recovery indirect.

Fix and after-result: a small test-only `127.0.0.1` fixture now binds one
ephemeral TCP port, performs only `version`/`verack`/`getbsman`, and closes its
own socket. It creates no datadir, wallet, snapshot files, or external
connection. The narrow test seam invokes the existing production reconnect
stream checker and closes its returned socket; it changes no production
transfer policy.

Regression proof: one deterministic fixture accepts the matching master
manifest, rejects the same manifest with a trailing byte, and rejects a
well-formed but divergent manifest identity. The focused loopback test and all
63 `bootstrap_snapshot_protocol_tests` cases pass after an incremental C++
build. `git diff --check` passes. ASan/UBSan remains unrun because 11 GB free
must preserve the 10 GB reserve; no legacy cyclomatic-complexity gate exists.
The unrelated broad RPC-wallet ECC-context failure remains explicitly
unaddressed.

Consensus impact: NONE. This is test-only loopback coverage around existing
bootstrap socket validation. Consensus serialization, chain history, PoW,
monetary policy, upgrades, block/transaction validity, and cryptography are
unchanged. Worldstream remains non-overlap storage/restart work at
`d9f5153be8fc59d140db9b6f59e796a7c668160a`. Remaining risk: use this fixture
to establish a bounded reconnect-after-transient-failure case before changing
parallel-stream retry behavior.

## Parallel bootstrap streams recover one transport reset

Baseline and root cause: every parallel snapshot stream opened exactly one
connection. A transient TCP reset before the manifest response—either before
or immediately after the bootstrap handshake—aborted the whole download and
discarded its staging, even when the same source was immediately reachable
again. The loopback fixture establishes both reset positions before serving
the matching manifest on the second connection.

Fix and after-result: reconnect-stream opening now has a strict two-attempt
budget until a `BSMAN` frame arrives. A reset while connecting, handshaking,
sending `getbsman`, or awaiting that first frame recovers once; once the frame
arrives, malformed or divergent manifest input remains fail-fast with its
precise existing error. The outer peer policy still owns broader source
failover, staging cleanup, and all snapshot validation. This recovers a one-off
transport reset without turning malformed source behavior into extra network
work.

Regression proof: the localhost fixture proves a matching manifest succeeds
after exactly one pre- or post-handshake reset, while its existing cases prove
trailing and divergent manifests still fail immediately. The focused case and all 63
`bootstrap_snapshot_protocol_tests` cases pass after an incremental C++ build.
`git diff --check` passes. ASan/UBSan is unrun: 11 GB free preserves the 10 GB
reserve but cannot safely fit a cold sanitizer build; this legacy checkout has
no cyclomatic-complexity gate. The unrelated broad RPC-wallet ECC-context
failure remains unaddressed and is not hidden.

Consensus impact: NONE. Only a bounded pre-manifest socket reconnect changes;
the compiled anchor, manifest identity check, per-file hashes, imported-state
verification, chain history, consensus serialization, PoW, monetary policy,
upgrades, block/transaction rules, and cryptography are unchanged. Worldstream
remains non-overlap storage/restart work. Remaining risk: a disconnect after a
stream has begun a chunk subset still falls through to the existing outer
snapshot retry; resume semantics require separate byte-accurate evidence.

### CI checkpoint

GitHub Actions run
[`36348225710`](https://github.com/CesareFI/zclassic-node-development/actions/runs/36348225710)
completed successfully for `15a741ab25297486bd3a5da2a7c737ee331c543a` on
2026-09-27. Dependency restore/build, CCache, the full Zclassic build, and
artifact upload all passed. This confirms both the bounded stream-open retry
implementation and the still-pinned native_ccache dependency path in the
published C++ development head; it does not claim sanitizer coverage.

### CI checkpoint: post-handshake retry boundary

GitHub Actions run
[`36349538788`](https://github.com/CesareFI/zclassic-node-development/actions/runs/36349538788)
completed successfully for `f86fb572b5eb963c0fd58ad2e13d3133599bcddb` on
2026-09-27. Dependency restore/build, CCache, full Zclassic build, and artifact
upload all passed. This validates the event-bound transport retry boundary;
sanitizer coverage remains unrun due to the preserved disk reserve.

## Bootstrap throughput watchdog uses monotonic elapsed time

Baseline and root cause: bootstrap snapshot and Zcash-parameter downloads used
`GetTimeMillis()` for their sustained-throughput windows and displayed rate.
That is wall-clock time, so an NTP correction or operator clock change could
spuriously expire a healthy transfer window or extend a stalled peer's window.
The block-download scheduler already uses the process-local steady clock for
the same elapsed-time safety property.

Fix and after-result: snapshot subset, parallel aggregate, and parameter
transfer accounting now obtain elapsed milliseconds from
`GetSteadyTimeMicros()`. Network message timeouts, protocol framing, chunk
order, request ownership, hashes, manifest checks, and all validation remain
unchanged. A narrow test seam exposes only the chosen elapsed clock; with the
existing deterministic steady-clock mock it returns 1234 ms for 1,234,567 us.

Regression proof: after an incremental `make -C src -j2 test/test_bitcoin`,
the focused `bootstrap_download_throughput_clock_is_monotonic` case and all
64 `bootstrap_snapshot_protocol_tests` cases pass. `git diff --check` passes.
ASan/UBSan remains unrun: 11 GB free preserves the required 10 GB reserve but
does not safely fit a cold sanitizer build. This legacy checkout has no
cyclomatic-complexity ratchet. The unrelated broad RPC-wallet ECC-context
collision remains unaddressed and is not hidden.

Consensus impact: NONE. Only local elapsed-time enforcement and presentation
for optional bootstrap/parameter transfers change; chain history, consensus
serialization, PoW, monetary policy, upgrades, block and transaction
validity, and cryptography are untouched. Worldstream remains non-overlap
storage/restart work at `d9f5153be8fc59d140db9b6f59e796a7c668160a`.
Remaining risk: a stream reset after chunk delivery still falls to the bounded
outer snapshot retry; byte-accurate resume needs separate loopback evidence.

## Bootstrap frame timeout cannot be extended by byte trickle

Baseline and root cause: bootstrap socket send/receive loops supplied their
full timeout to every retry after a partial socket operation. A peer could keep
a header or payload alive by making periodic small progress, repeatedly buying
another full `select()` timeout. `ReceiveExpectedBootstrapMessage` also used a
wall-clock deadline, and its frame reader could separately spend that remaining
budget on the header and payload.

Fix and after-result: each write, complete receive frame (header plus payload),
and expected-message wait now derives one overflow-safe deadline from
`GetSteadyTimeMicros()`. Every retry computes the rounded-up remaining
milliseconds; expiration retains the existing read/write/expected-message
timeout errors. A ping response uses the same residual budget. No socket is
reopened, no message is retried, and no protocol/validation behavior changes.

Regression proof: the deterministic mock-clock case starts a 60 ms budget at
1,000,000 us, verifies 60 ms remains after one microsecond, one ms remains at
the final microsecond, and zero remains at expiry; it also proves a saturated
deadline clamps to `INT_MAX` milliseconds without signed rounding overflow.
This directly covers the helpers used around every partial socket operation.
After incremental rebuild, the focused case and all 65
`bootstrap_snapshot_protocol_tests` cases pass; `git diff --check` passes.
ASan/UBSan remains unrun because 11 GB free must
retain the 10 GB reserve; this legacy checkout has no cyclomatic-complexity
ratchet. The unrelated broad RPC-wallet ECC-context collision remains
unaddressed and is not hidden.

Consensus impact: NONE. This is bounded timeout accounting for optional
bootstrap transport only; chain history, consensus serialization, PoW,
monetary policy, upgrades, block/transaction validity, and cryptography are
untouched. Worldstream remains non-overlap storage/restart work at
`d9f5153be8fc59d140db9b6f59e796a7c668160a`. Remaining risk: post-chunk
stream recovery still uses the existing outer snapshot retry rather than a
byte-accurate resume protocol.

## Bootstrap chunk-stream reset retries one verified stream

Baseline and root cause: parallel bootstrap workers retried a transient reset
while opening or fetching their manifest, but a socket reset after a verified
manifest immediately cancelled every worker and discarded the entire staging
attempt. This could waste already verified files and make one flaky TCP stream
stall fresh-node bootstrap progress.

Fix and after-result: each parallel worker now gets one additional attempt
only when a socket send, receive, ping reply, or deadline expires during its
chunk transfer. A reconnect repeats the normal handshake and exact manifest
identity check. It retains only final files whose SHA-256 has already verified;
an unfinished `.part` is overwritten from offset zero and its provisional
progress is removed. Malformed framing/chunks, unexpected chunk ownership,
rejects, divergent manifests, hash mismatch, local I/O errors, and shutdown
remain terminal. The retry is per worker, bounded at two attempts, and never
trusts data before the existing per-file hash and later import validation.

Regression proof: a localhost-only C++ loopback fixture serves one valid chunk
of a deterministic three-chunk file, resets the connection, then requires the
client to reconnect, re-fetch the exact manifest, request the file from zero,
and hash the final 257-byte result. The focused case and all 66
`bootstrap_snapshot_protocol_tests` cases pass after an incremental build;
`git diff --check` passes. The fixture uses a unique disposable directory on
the build filesystem because this host's `/tmp` has only about 200 MB and the
real downloader correctly reserves a 1 GiB staging margin. ASan/UBSan remains
unrun: 11 GB free preserves the required 10 GB reserve but cannot safely fit a
cold sanitizer build. This legacy checkout has no cyclomatic-complexity gate.
The unrelated broad RPC-wallet ECC-context collision remains unaddressed and
is not hidden.

Consensus impact: NONE. Only optional bootstrap transport retry and progress
accounting change; chain history, consensus serialization, PoW, monetary
policy, upgrades, block/transaction validity, and cryptography are untouched.
Worldstream remains non-overlap C23 storage/startup work at
`d9f5153be8fc59d140db9b6f59e796a7c668160a`. Remaining risk: recovery retries
the same peer rather than changing sources; peer-diverse manifest acquisition
under reconnect churn is the recommended next networking investigation.

## Bootstrap discovery rejects unroutable advertised endpoints

Baseline and root cause: the pre-database bootstrap discovery parser accepted
any syntactically valid `NODE_BOOTSTRAP` address. Unlike normal P2P `addr`
handling, that included loopback and RFC1918 endpoints. A responding discovery
peer could therefore consume the small direct-dial budget with local or private
addresses, reducing healthy-source diversity and causing unwanted local-network
connection attempts.

Fix and after-result: discovery now requires both `IsValid()` and
`IsRoutable()` before retaining an advertised endpoint, matching ordinary P2P
address policy. The bounded result count, exact-payload check, service-bit
requirement, and transport behavior are otherwise unchanged.

Regression proof: the existing deterministic decoder fixture now mixes a
routable advertised bootstrap endpoint with duplicate, non-bootstrap, loopback,
and RFC1918 entries; only the single routable unique bootstrap endpoint is
retained. The focused decoder case passes after incremental compilation.

Consensus impact: NONE. This only filters untrusted optional peer-discovery
advertisements before dialing; chain history, consensus serialization, PoW,
monetary policy, upgrades, block/transaction validity, and cryptography are
unchanged. Worldstream remains non-overlap C23 storage/startup work at
`d9f5153be8fc59d140db9b6f59e796a7c668160a`. Remaining risk: diversity is
endpoint-level rather than autonomous-system-level; a later bounded source
selection study should measure repeated advertisements across reconnect churn.

## Bootstrap seed candidates preserve bounded dial diversity

Baseline and root cause: before discovery dials its maximum three seed
candidates, DNS and fixed-seed results were appended without routability or
duplicate filtering. Repeated resolver data could therefore spend all probes
on one endpoint; local/private results could consume probes before normal
addrman policy existed.

Fix and after-result: a shared candidate-admission helper accepts only unique,
routable `CService` endpoints. Both DNS and fixed-seed paths use it, preserving
first-seen order and existing global caps.

Regression proof: a deterministic native test admits two routable endpoints
while rejecting a duplicate, loopback, and RFC1918 candidate, and verifies the
two retained endpoints stay ordered. The focused case passes after incremental
compilation.

Consensus impact: NONE. Optional pre-database bootstrap-peer candidate
selection only; chain history, consensus serialization, PoW, monetary policy,
upgrades, block/transaction validity, and cryptography are unchanged.
Worldstream remains non-overlap C23 storage/startup work at
`d9f5153be8fc59d140db9b6f59e796a7c668160a`. Remaining risk: routable address
diversity is not autonomous-system diversity; measure source concentration
before considering more complex selection policy.

## Discovered bootstrap peers get bounded round-robin recovery

Baseline and root cause: configured bootstrap peers receive three round-robin
attempts, but opt-in discovered peers were attempted only once. A source reset
during its initial connection could therefore discard the entire discovered
fallback despite other recovery paths being bounded and restart-safe.

Fix and after-result: discovered peers now use the existing retry scheduler for
two rounds. Every source receives its first attempt before any source receives
a second; the existing three-second pause remains only between rounds.

Regression proof: incremental compilation passes; the deterministic retry
schedule regression and all 67 `bootstrap_snapshot_protocol_tests` pass.

Consensus impact: NONE. This changes optional bootstrap transport availability
only; chain history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream
remains non-overlap C23 storage/startup work. Remaining risk: discovery still
depends on available seed responses; normal P2P fallback remains unchanged.

## Malformed `notfound` releases assigned block work

Baseline and root cause: `ProcessNotFound()` decoded the peer-controlled reply
directly. A truncated reply threw into generic message handling, which rejected
it but only performs immediate download teardown for malformed `block` and
`headers` messages. The malformed `notfound` sender therefore retained its
assigned block window until the ordinary download deadline, delaying a healthy
source's takeover.

Fix and after-result: bounded, oversized, truncated, and trailing `notfound`
replies now score the sender, disconnect it, and synchronously release only
that node's block requests and download roles. A well-formed owned `notfound`
still remains a non-ban availability failure; unrelated peers cannot release
another source's work.

Regression proof: the native block-download fixture assigns a 128-block window
and supplies oversized, truncated, and trailing replies. A fragmented wire
frame with an incomplete `CInv` also reaches the real dispatcher and performs
the same cleanup. Each leaves zero in-flight validated blocks before a healthy
peer can receive the next window. The focused regression, valid
unavailable-source takeover, forged-`notfound` ownership, and
socket-disconnect teardown regressions pass after an incremental `test_bitcoin`
rebuild. `git diff --check` passes. ASan/UBSan is unrun: 11 GB
free must preserve the 10 GB reserve, and this legacy checkout has no
cyclomatic-complexity gate.

Consensus impact: NONE. This is P2P error and ownership cleanup only; chain
history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are untouched. Worldstream's
latest available C23 `origin/main` is
`58c38837a637979842dfe84fcfc86d33c6781d52` (capability-inventory regeneration),
so this remains non-overlap networking work. Remaining risk: malformed replies
still rely on normal transport framing before this handler is reached.

## Wallet-suite ECC report: current bounded reproduction

The historical September broad-suite report itself is unavailable in the
preserved evidence. Its repeated `ECC_Start()` assertions cannot be explained
by separate test processes because `secp256k1_context_sign` is process-local.
Within a `test_bitcoin` process, each `TestingSetup` starts ECC and its derived
teardown joins script-check threads before the base fixture calls `ECC_Stop()`.
All 21 registered `rpc_wallet_tests` cases, including both parallel async
operations cases, pass individually with the existing binary and its isolated
per-fixture datadir. The complete group could not be observed because this
session's bounded command runner stops it at 30 seconds; that is not a pass or
failure. No fixture defect is demonstrated, so no assertion or security check
was changed. Recommended next investigation: retain the original broad-suite
command/output, then reproduce its first failing case in the same process.

## Loopback bootstrap reconnect fixture is deadline-bounded

Baseline and root cause: an externally owned run of the chunk-reset loopback
regression remained active for more than 15 hours. The current source could not
attribute that job's state without interfering with it, but its test server had
unbounded `accept`, `recv`, and `send` calls. A missing reconnect could therefore
block the test harness indefinitely and hide the first failed protocol step.

Fix and after-result: the localhost-only fixture now uses a five-second
readiness deadline for accepts and each socket read/write. It reports its
existing protocol failure instead of waiting indefinitely; production bootstrap
socket code is unchanged. A new bounded local run of the exact chunk-reset
regression completed successfully in 15.7 seconds with `timeout 20s`.

Regression proof: incremental `test_bitcoin` rebuild plus the one-case
loopback reset/reconnect test passed. The broader bootstrap group is not rerun
because an unrelated session owns a long-running instance and the 10 GB disk
reserve forbids sanitizer builds. `git diff --check` passes. Consensus impact:
NONE. Worldstream remains non-overlap C23 startup/storage work. Remaining risk:
the pre-existing external process must be diagnosed by its owning session; it
was not terminated or modified here.

## Peer misbehavior scoring owns its node-state lock

Baseline and root cause: `Misbehaving()` reads and mutates `mapNodeState`, and
its contract said callers must hold `cs_main`. The normal message thread holds
only the peer receive-buffer lock while dispatching `ProcessMessage()`, leaving
many malformed-message score paths unsynchronized with disconnect, RPC, and
validation state changes.

Fix and after-result: `Misbehaving()` now acquires the recursive `cs_main`
itself. Callers already inside validation continue safely through recursive
locking; receive-thread parsing paths now use the same state ownership rule.
No scoring thresholds, bans, wire rules, or validation decisions changed.

Regression proof: incremental `test_bitcoin` rebuild plus malformed-header
takeover, trailing-block takeover, malformed-`notfound` cleanup, and malformed
bootstrap-chunk scoring cases pass. `git diff --check` passes. The initial
unqualified bootstrap filter was rejected by Boost and is explicitly not counted
as a test result; the suite-qualified case passed. ASan/UBSan remains unrun due
the 11 GB free / 10 GB reserve boundary.

Consensus impact: NONE. This serializes existing peer-state accounting only;
chain history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream remains
non-overlap C23 checked-store work. Remaining risk: full race exploration still
requires a sanitizer-capable build profile.

## Invalid P2P wire headers release assigned downloads

Baseline and root cause: the framed message loop logged an invalid P2P header
(such as an invalid command byte) and continued the connection. An assigned
peer could repeatedly send invalid framing while retaining its block window;
the broad fuzz regression had to force teardown in test code.

Fix and after-result: invalid wire headers now mark the peer disconnected and
return failure from the framed dispatcher. Normal disconnect cleanup releases
only that peer's header role and in-flight blocks for immediate healthy-source
takeover. Checksum-mismatch handling remains unchanged.

Regression proof: a fragmented wire frame with a valid checksum but invalid
command byte reaches the real header validator while owning 128 requests. It
disconnects, clears accounting on the next scheduler visit, and a healthy peer
receives the full window. The new test and existing truncated-block framed
cleanup case pass after an incremental `test_bitcoin` build; `git diff --check`
passes. The broad fragmented fuzz group was not rerun after the command runner
reached its 30-second cap before results; it is not claimed as passing.

Consensus impact: NONE. This is P2P framing and download-lifetime cleanup only;
chain history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream remains
non-overlap C23 checked-store work. Remaining risk: valid checksummed but
semantically malformed commands use their command-specific validation paths.

## Invalid P2P checksums release assigned downloads

Baseline and root cause: the message loop logged a failed application checksum
then kept the connection alive. TCP already protects the byte stream, so this
is a malformed peer frame rather than a recoverable partial read. A source
could repeatedly send checksum-invalid messages while retaining its block
window until timeout.

Fix and after-result: checksum mismatch now marks the peer disconnected and
returns failure from framed dispatch, matching invalid header behavior. Normal
disconnect cleanup releases only that source's assignments for immediate
healthy-peer takeover.

Regression proof: a fragmented, otherwise valid message with a corrupt wire
checksum reaches the framed checksum validator while owning 128 blocks. It
disconnects, releases accounting on the next scheduler visit, and a healthy
peer receives the full window. The new checksum regression and invalid-header
takeover regression pass after an incremental `test_bitcoin` build; `git diff
--check` passes. ASan/UBSan remains unrun due the 11 GB free / 10 GB reserve
boundary.

Consensus impact: NONE. This changes malformed P2P framing cleanup only; chain
history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream remains
non-overlap C23 verification-profile work. Remaining risk: well-formed but
slow peers continue through the existing monotonic timeout/reassignment path.

## Broader block-download validation after recovery hardening

The complete registered `block_download_tests` group now runs to completion with
the existing binary: 63 cases passed in approximately 65 seconds under a
120-second bounded terminal session. It covers the new malformed wire/header
cleanup paths alongside timeout, reassignment, ownership, peer-priority,
header-progress, import-pause, reconnect, and bounded-request regressions.
The measured idle scheduler remained 0.0303 seconds for 125 peers and 0.1532
seconds for 750 peers over 1,000 rounds; no scheduler optimization is claimed
from this measurement. Consensus impact: NONE. ASan/UBSan remains unrun due the
11 GB free / 10 GB reserve boundary.

## Complete bootstrap protocol regression validation

The complete registered `bootstrap_snapshot_protocol_tests` group now runs to
completion with the existing binary: all 67 cases passed in 13.8 seconds under
a 120-second bounded terminal session. This covers bootstrap manifest/chunk
framing, bounded retries, stream-reset reconnect, discovery endpoint admission,
peer retry rotation, malformed bootstrap message scoring, and the new
deadline-bounded localhost fixture. Consensus impact: NONE. ASan/UBSan remains
unrun because 11 GB free preserves the required 10 GB reserve.

Worldstream's latest C23 `origin/main` is
`fd9f5217de6e5f80bb45abf05bd503c7f89ef602` (GCC14 verification profile/staging
contract), which remains non-overlap work.

Complementary native networking validation: the existing binary also passed
all 8 `netbase_tests` cases and all 6 `net_selection_tests` cases under
60-second bounds. These cover address/network primitives and peer-selection
behavior; they do not claim full end-to-end IBD acceptance.

Read-only follow-up evidence: the pre-existing process's main thread is in a
futex wait while joining its test server, and that server thread is blocked in
`accept` on the loopback listener (socket inode `61033212`). It is waiting for
the reconnect that never arrived. This confirms the test-fixture hang mechanism
without inspecting or modifying the process's data; the bounded listener path
in this branch is the targeted regression prevention.

## Unsolicited full header batches cannot restart completed discovery

Baseline and root cause: the headers handler requested a continuation after
every maximum-size valid batch with no check that this peer still owned a
header-sync role. A peer that had already returned an empty/short response
could repeatedly send valid historical full batches and make the node emit a
new `getheaders` request each time, with no active discovery deadline.

Fix and after-result: a continuation is now emitted only while that peer has
an outstanding header-sync role. Unsolicited headers continue through their
existing validation and availability tracking path, but cannot create a new
request loop. Active slow discovery still advances its monotonic deadline only
when chain work advances, preserving normal headers-first sync.

Regression proof: a deterministic peer completes discovery with an empty
response, then supplies a valid maximum header batch; it receives no second
`getheaders`, owns no header role, and has no deadline. The new regression plus
the existing repeated-full-batch deadline and advancing-slow-discovery cases
pass after an incremental `test_bitcoin` build. `git diff --check` passes.
ASan/UBSan remains unrun because 11 GB free preserves the 10 GB reserve; this
legacy checkout has no cyclomatic-complexity ratchet.

Consensus impact: NONE. This only prevents unsolicited P2P response loops;
chain history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream's
latest C23 `origin/main` remains capability-inventory-only work at
`58c38837a637979842dfe84fcfc86d33c6781d52`. Remaining risk: a peer with an
active requested range can still legitimately provide maximum batches until
the existing progress or deadline rules end that role.

## Explicit malformed headers release block assignments

Baseline and root cause: parse exceptions from a malformed `headers` reply
already disconnected a peer, but explicit checks for an oversized count,
nonzero legacy transaction count, or trailing bytes only added misbehavior.
If such a peer already owned requested block bodies, its assignments remained
unavailable until the ordinary timeout.

Fix and after-result: all explicit malformed-header exits now mark the peer for
disconnect, matching the exception path. Normal disconnect cleanup releases its
header role and only its own in-flight blocks, allowing another source to take
them immediately.

Regression proof: a deterministic peer first owns a 128-block window, then
sends a header payload with trailing data. The next scheduler visit clears all
its accounting, and a healthy peer receives the full window. The new takeover
case, existing trailing-header validation case, and truncated framed-header
teardown case pass after an incremental `test_bitcoin` build. `git diff --check`
passes. ASan/UBSan remains unrun due the 11 GB free / 10 GB reserve boundary.

Consensus impact: NONE. This is malformed P2P response cleanup only; chain
history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream remains
non-overlap C23 capability-inventory work. Remaining risk: valid but silent
sources continue to use the existing bounded download timeout path.

Follow-up safety correction: `Misbehaving()` requires `cs_main`. The explicit
malformed-header and trailing-block exits now acquire that recursive lock before
changing the peer score, matching the node-state ownership contract. The same
malformed-header takeover, nonzero-count header, and trailing-block takeover
regressions pass after incremental rebuild; consensus impact remains NONE.

## Block messages require exact wire consumption

Baseline and root cause: the block handler deserialized one `CBlock` but did
not reject trailing bytes. A peer could append arbitrary data after a valid
requested block; the valid prefix was accepted and the malformed frame was
neither scored nor disconnected.

Fix and after-result: the handler now requires the block payload to be fully
consumed before it records inventory or invokes validation. A trailing byte is
a malformed P2P frame, scores the sender, and follows normal disconnect cleanup
so its assigned work is immediately available to another source.

Regression proof: a source holding a 128-block window sends a valid first block
with one trailing byte. The chain remains at height zero, teardown clears its
accounting, and a healthy source receives the full window. The new regression,
invalid-block reject encoding, and foreign-invalid-body ownership regression
pass after an incremental `test_bitcoin` build. `git diff --check` passes.
ASan/UBSan remains unrun because 11 GB free preserves the 10 GB reserve.

Consensus impact: NONE. This rejects malformed network framing before block
validation; chain history, consensus serialization, PoW, monetary policy,
upgrades, block/transaction validity, and cryptography are unchanged.
Worldstream's latest C23 head is `3556ff3c47ad89dc7a6d8e635b00901aff69cfba`
(checked-store issuer-log work), so this remains non-overlap networking work.
Remaining risk: valid block bodies from a silent source still use the existing
monotonic timeout/reassignment path.

## Malformed inventory cannot retain a block-download window

Baseline and root cause: malformed `inv` input was scored or logged, but a
source that already owned block bodies was not disconnected. A truncated
inventory reached the generic deserialization catch, and a trailing or
oversized inventory returned failure from the command handler; neither path
released the source's assigned window until the normal timeout.

Fix and after-result: malformed inventory deserialization now follows the
existing malformed block/header teardown path. Explicit oversized and trailing
inventory checks also mark the source disconnected. Normal disconnect cleanup
releases only that peer's assignments, so a healthy peer can take the complete
128-block window immediately.

Regression proof: two fragmented real-frame tests cover a declared-but-missing
inventory entry and a valid empty inventory with one trailing byte. Each starts
with 128 assigned blocks, observes prompt teardown and zero global accounting,
then verifies a healthy peer receives all 128 requests. Both new cases and the
existing trailing-inventory no-scheduling regression passed after an
incremental `test_bitcoin` build; all six `net_selection_tests` cases and
`git diff --check` also pass. A bounded complete block-download run was
observed through its scheduler measurements but its detached terminal did not
preserve an exit receipt, so it is not recorded as a passing validation for
this slice. ASan/UBSan remains unrun because 11 GB free preserves the required
10 GB reserve.

Consensus impact: NONE. This is malformed P2P inventory teardown only; chain
history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream's
latest C23 `origin/main` is `fd9f5217de6e5f80bb45abf05bd503c7f89ef602`
(GCC14 verification profile/staging contract), with no overlap. Remaining
risk: valid but silent block sources continue through the existing monotonic
timeout/reassignment path. Recommended next investigation: use bounded
offline tests to examine whether duplicate unsolicited valid inventory can
distort peer availability without changing block ownership.

## Command failures release assigned downloads consistently

Baseline and root cause: framed dispatch logged every `ProcessMessage` false
result but only deserialization exceptions for `block`, `headers`, and now
`inv` explicitly disconnected the peer. A source holding block bodies could
send another malformed command, such as `getheaders` with trailing bytes, and
retain its assigned window until the ordinary timeout.

Fix and after-result: a command-handler failure now tears down the sending
peer after the existing failure log. This is the common failure boundary for
malformed and invalid P2P command input; normal disconnect cleanup releases
only that peer's outstanding block requests and leaves other sources intact.

Regression proof: a fragmented, checksummed `getheaders` frame with one
trailing byte is sent by a peer owning 128 requested blocks. It disconnects,
clears per-peer and global accounting, and a healthy peer receives the full
window. The new case and the refactored trailing-inventory takeover case pass
after an incremental `test_bitcoin` build. The complete
`block_download_tests` group passed 66/66 with an explicit zero exit status;
the measured idle scheduler was 0.0244 seconds for 125 peers and 0.1602
seconds for 750 peers over 1,000 rounds. This is validation coverage, not a
claimed scheduler performance improvement. `git diff --check` passes.
ASan/UBSan remains unrun because 11 GB free preserves the required 10 GB
reserve.

Consensus impact: NONE. This changes P2P teardown after a local command
failure only; chain history, consensus serialization, PoW, monetary policy,
upgrades, block/transaction validity, and cryptography are unchanged.
Worldstream's latest C23 `origin/main` is
`ab1deafdcc35d1cdec30148327dd935636ccbe67` (test RAM scratch reservation),
with no overlap. Remaining risk: valid, non-progressing block sources still
use the existing monotonic timeout/reassignment path. Recommended next
investigation: bounded peer-availability tests for repeated unknown inventory
under reconnect churn, without changing source ownership unless evidence
shows a scheduling defect.

## Inventory send-buffer abort releases existing assignments

Baseline and root cause: repeated unknown inventory is bounded by the existing
MRU and request caps, and the command handler already cancels only reservations
that have not been queued when its send buffer aborts. The newly centralized
framed command-failure teardown needed a wire-level proof that an older,
actually queued block request is also released when the peer is disconnected.

After-result and regression proof: a localhost-only framed `inv` sequence
first obtains one block request, then triggers the existing 1,000-byte
send-buffer abort with a bounded historical inventory batch. Framed dispatch
disconnects the source, clears all per-peer and global accounting, and a
healthy source immediately takes 128 requests including the formerly queued
block. The new wire test and the existing direct reservation-preservation test
pass after incremental build. The complete `block_download_tests` group passed
67/67 with explicit zero exit status; idle scheduling measured 0.0233 seconds
for 125 peers and 0.1544 seconds for 750 peers over 1,000 rounds. No scheduler
performance gain is claimed. `git diff --check` passes. ASan/UBSan remains
unrun because 11 GB free preserves the required 10 GB reserve.

Consensus impact: NONE. This adds deterministic P2P scheduler coverage only;
chain history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream's
latest C23 `origin/main` remains
`ab1deafdcc35d1cdec30148327dd935636ccbe67` (test RAM scratch reservation),
with no overlap. Remaining risk: a valid, slow source remains governed by the
existing monotonic timeout/reassignment path. Recommended next investigation:
exercise peer availability after reconnect churn with bounded valid headers
and unknown inventory, then change scheduling only if ownership or availability
evidence is lost.

## Disconnected peers release unlinked block provenance

Baseline and root cause: `mapBlockSource` retains the NodeId that supplied an
accepted body until that block connects. A valid child body can remain unlinked
while its parent is still missing; if its source disconnects, retaining that
NodeId cannot produce a reject or a penalty, but consumes tracking memory for
the rest of the process.

Fix and after-result: `DisconnectNode` now removes provenance entries as soon
as socket teardown releases download work; deferred `FinalizeNode` repeats the
same cleanup idempotently. The existing downloader diagnostic snapshot exposes
the bounded tracked-source count, making this lifecycle state directly testable
without changing P2P or consensus behavior.

Regression proof: a peer supplies requested block 2 before block 1, producing
one valid unlinked body and one tracked source while the active chain remains
at height zero. Socket-disconnect cleanup reduces the tracked-source count to
zero, and deferred finalization preserves zero. The new teardown case and
existing foreign-invalid-body ownership case pass after incremental build. The
complete `block_download_tests` group passed 68/68 with explicit zero exit
status; idle scheduling measured 0.0238 seconds for 125 peers and 0.1601
seconds for 750 peers over 1,000 rounds. No scheduler performance gain is
claimed. `git diff --check` passes. ASan/UBSan remains unrun because 11 GB free
preserves the required 10 GB reserve.

Consensus impact: NONE. This releases disconnected-peer provenance metadata
only; chain history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream's
latest C23 `origin/main` is
`e55ca12385d26e6f3ed5b1d47c47537e47a11b21` (CAS proof-head recovery), with no
overlap. Remaining risk: connected peers can still retain provenance for valid
unlinked bodies until normal chain processing resolves them. Recommended next
investigation: bounded accounting for prolonged connected unlinked-body
sources, only if live fixture evidence shows measurable growth.

## Unsolicited bootstrap chunks release block ownership

Baseline and root cause: the snapshot bootstrap client uses a dedicated socket,
so `BSCHK` and `BSPCHK` received over an ordinary CNode connection are never
requested. They were lightly scored after bounded decoding but remained
connected, allowing a source that already owned block bodies to retain its
window until the regular timeout or ban threshold.

Fix and after-result: a valid unsolicited bootstrap chunk now marks the source
for normal teardown immediately after the existing bounded parse and score.
Malformed chunks still fail through their existing scored failure path; neither
path accepts snapshot content into ordinary P2P block processing.

Regression proof: two fragmented wire cases cover snapshot and parameter
chunks. Each peer first owns 128 requested blocks, sends a valid one-byte
unsolicited chunk, disconnects, clears per-peer/global accounting, and yields
the full window to a healthy peer. Both cases pass after incremental build.
The complete `bootstrap_snapshot_protocol_tests` group passed 67/67 and the
complete `block_download_tests` group passed 70/70 with explicit zero exit
status. Idle scheduling measured 0.0243 seconds for 125 peers and 0.1605
seconds for 750 peers over 1,000 rounds; no performance improvement is
claimed. `git diff --check` passes. ASan/UBSan remains unrun because 11 GB free
preserves the required 10 GB reserve.

Consensus impact: NONE. This is ordinary-P2P extension teardown only; chain
history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream's
latest C23 `origin/main` is
`e55ca12385d26e6f3ed5b1d47c47537e47a11b21` (CAS proof-head recovery), with no
overlap. Remaining risk: valid but silent conventional block sources continue
through the monotonic timeout/reassignment path. Recommended next
investigation: verify that other non-block extension messages cannot retain an
assigned block window after a protocol-state violation.

## Unsolicited bootstrap manifests release block ownership

Baseline and root cause: the dedicated bootstrap client socket is the only
consumer of `BSMAN` and `BSPMAN`. Complete replies arriving on an ordinary
`CNode` socket were lightly scored, but the peer remained usable and could
retain an assigned 128-block window until normal timeout even though the
message cannot advance bootstrap work on that connection.

Fix and after-result: after the existing bounded decode and score, both
ordinary-P2P manifest handlers now request normal disconnect. The established
teardown releases only scheduler ownership; malformed framing, manifest
validation, chunk/hash verification, snapshot installation, and all consensus
checks are unchanged.

Regression proof: two fragmented localhost-only wire cases send complete,
serializable snapshot and parameter manifests after the source owns 128 block
requests. Each case proves disconnect, zero per-peer/global request accounting,
and immediate full-window takeover by a healthy peer. The direct regression
passes. The full `bootstrap_snapshot_protocol_tests` group passes 67/67 and
the full `block_download_tests` group passes 72/72 after the incremental native
rebuild; the latter measured 0.0247 seconds for 125 idle peers and 0.1508
seconds for 750 peers over its existing 1,000-round scheduling checks. No
performance gain is claimed. `git diff --check` passes. ASan/UBSan is unrun:
11 GB free preserves the required 10 GB reserve and no reusable sanitizer
binary is present.

Consensus impact: NONE. This is CNode protocol-state teardown only; chain
history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream's
latest C23 `origin/main` is
`263b06ffd0460b9fd54a7e5e21f23d80463bf8fb` (capability-inventory regeneration
after CAS proof-head recovery), with no overlap. Remaining risk: conventional
but silent sources remain governed by the existing monotonic
timeout/reassignment path. Recommended next investigation: use the bounded
loopback bootstrap driver tests to establish whether reconnect churn can let
one manifest source monopolize all stream attempts before changing diversity
policy.

## Ignored far-ahead blocks do not retain source provenance

Baseline and root cause: `ProcessNewBlock` recorded `mapBlockSource` whenever
`AcceptBlock` returned a block index, including an unrequested body that
`AcceptBlock` intentionally declined to store because it was too far ahead of
the active tip. That source entry had no possible later validation or reject
work, yet could accumulate while a connected peer sent otherwise-valid
far-ahead bodies.

Fix and after-result: provenance is now retained only when `AcceptBlock`
succeeds and the index has `BLOCK_HAVE_DATA`. Requested and accepted unlinked
bodies still retain their source for delayed validation; ignored, unrequested
bodies do not. No block acceptance predicate, storage decision, or peer wire
behavior changed.

Regression proof: the downloader fixture validates headers through original
mainnet height 320, then supplies the authentic 1,587-byte height-320 body as
an unrequested block while the active chain remains at height zero. The block
is correctly ignored by the existing far-ahead rule and now leaves tracked
source accounting at zero. Its compact source vector is checked byte-for-byte
against the preserved historical archive during this development run. The
focused case and the complete `block_download_tests` group pass 73/73 after an
incremental native rebuild; idle scheduling measured 0.0236 seconds for 125
peers and 0.1532 seconds for 750 peers over the existing 1,000-round checks.
No throughput improvement is claimed. `git diff --check` passes. ASan/UBSan
remains unrun: 11 GB free preserves the required 10 GB reserve and no reusable
sanitizer binary exists.

Consensus impact: NONE. This bounds non-consensus source metadata only; chain
history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream's
latest C23 `origin/main` is
`3a3caa86c0d9afec3a60954f12353c78c80750f6` (capability-inventory
regeneration), with no overlap. Remaining risk: accepted unlinked bodies
properly retain provenance until connection or chain-processing cleanup;
investigate source retention only with evidence that those accepted bodies
exceed the scheduler's bounded request windows.

## Accepted unlinked bodies retain bounded provenance until connection

Baseline evidence: source attribution must remain available for a valid
requested body whose parent is missing, because later contextual processing can
still require a reject or penalty. The preceding ignored-body fix deliberately
does not alter this accepted-body path.

Regression proof: one peer receives its normal 128-block request window, then
delivers children 2 through 128 before block 1. The active chain remains at
zero, one request remains outstanding, and exactly 127 source entries are
retained. Delivery of block 1 connects the complete range through height 128
and consumes every entry. The focused case and complete
`block_download_tests` group pass 74/74 after incremental compilation; idle
scheduling measured 0.0234 seconds for 125 peers and 0.1803 seconds for 750
peers over the existing 1,000-round checks. The timing is observability only,
not a performance claim. `git diff --check` passes. ASan/UBSan remains unrun:
11 GB free preserves the required 10 GB reserve.

Consensus impact: NONE. This regression documents existing non-consensus
metadata lifetime only; no production behavior changed. Worldstream's latest
C23 `origin/main` remains `3a3caa86c0d9afec3a60954f12353c78c80750f6`, with
no overlap. Remaining risk: provenance can grow only with bodies admitted by
the bounded request scheduler or separately accepted chain work; investigate a
different scheduler/peer diversity bottleneck rather than broadening this
metadata path without new evidence.

## Trailing ping payloads release block ownership

Baseline and root cause: the ordinary P2P `ping` handler decoded its BIP31
nonce but did not require payload exhaustion. A peer holding a block window
could send a checksum-valid nonce plus trailing bytes, remain connected, and
hold its requests until normal timeout despite violating the fixed-shape wire
message.

Fix and regression proof: modern pings now require exactly one nonce, while
pre-BIP31 pings require an empty payload. A fragmented wire regression gives a
peer 128 requested blocks, supplies a nonce plus one byte, and proves normal
teardown clears all accounting before a healthy peer takes the entire window.
The focused case and full `block_download_tests` group pass 75/75 after an
incremental rebuild; idle scheduling measured 0.0238 seconds for 125 peers and
0.1517 seconds for 750 peers over existing 1,000-round checks. No performance
gain is claimed. `git diff --check` passes. ASan/UBSan remains unrun to retain
the 10 GB disk reserve (11 GB free).

Consensus impact: NONE. This is bounded P2P framing validation only; chain
history, consensus serialization, PoW, monetary policy, upgrades,
block/transaction validity, and cryptography are unchanged. Worldstream's
latest C23 `origin/main` remains `3a3caa86c0d9afec3a60954f12353c78c80750f6`,
with no overlap. Remaining risk: malformed `pong` remains diagnostic-only by
design; it cannot advance block ownership and should not be treated as an IBD
source failure without evidence.

## Trailing verack payloads release block ownership

Baseline and root cause: `verack` is an empty handshake message, but the native
handler accepted a trailing payload. A peer that already held block requests
could therefore violate handshake framing without entering ordinary command
failure teardown.

Fix and regression proof: `verack` now requires payload exhaustion before it
marks a peer connected. A fragmented one-byte `verack` frame from a 128-request
source disconnects, clears all accounting, and lets a healthy peer take the
window. The focused regression and complete `block_download_tests` group pass
76/76 after incremental build; idle scheduling measured 0.0237 seconds for
125 peers and 0.1616 seconds for 750 peers over the existing 1,000 rounds. No
performance claim is made. `git diff --check` passes; ASan/UBSan is unrun to
retain the 10 GB reserve (11 GB free).

Consensus impact: NONE. This is P2P handshake framing only. Chain history,
consensus serialization, PoW, monetary policy, upgrades, block/transaction
validity, and cryptography are unchanged. Worldstream's latest C23
`origin/main` is `8cdab5ac0f8fef43ca7538e13728980df35b0a78`, with no overlap.

## Trailing version payloads fail before handshake completion

Baseline and root cause: after parsing the optional version fields, the native
handler accepted residual wire bytes and could mark the peer successfully
connected. The ordinary framed dispatcher then had no failure signal for this
malformed handshake.

Fix and regression proof: the handler now requires exact payload exhaustion.
A fragmented valid version frame with one trailing byte disconnects before
sync state is established. The focused regression passes, and the complete
`block_download_tests` group passes 77/77 after the committed incremental
build; idle scheduling measured 0.0235 seconds for 125 peers and 0.1564
seconds for 750 peers over existing 1,000-round checks. No performance claim
is made. `git diff --check` passes. ASan/UBSan remains unrun to preserve the
10 GB reserve (11 GB free).

Consensus impact: NONE. This is P2P handshake framing only; chain history,
consensus serialization, PoW, monetary policy, upgrades, block/transaction
validity, and cryptography are unchanged. Worldstream's latest C23
`origin/main` remains `8cdab5ac0f8fef43ca7538e13728980df35b0a78`, with no
overlap.

## Trailing getaddr payloads release block ownership

Baseline and root cause: inbound `getaddr` is a fixed-shape empty request, but
the handler accepted residual bytes before clearing and populating its address
response queue. A malformed source holding block requests could remain alive
until ordinary timeout.

Fix and regression proof: the request now requires payload exhaustion. A
fragmented one-byte `getaddr` from a 128-request source disconnects, clears
global ownership, and lets a healthy peer take the window. The focused case
and complete `block_download_tests` group pass 78/78 after incremental build;
idle scheduling measured 0.0281 seconds for 125 peers and 0.1589 seconds for
750 peers over existing 1,000 rounds. No performance claim is made.
`git diff --check` passes. ASan/UBSan remains unrun to preserve the 10 GB
reserve (11 GB free).

Consensus impact: NONE. This is P2P request framing only; chain history,
consensus serialization, PoW, monetary policy, upgrades, block/transaction
validity, and cryptography are unchanged.

## Trailing mempool payloads avoid unnecessary relay work

Baseline and root cause: `mempool` is an empty request, but the handler accepted
residual bytes before querying and iterating the transaction pool. A malformed
peer holding block requests could consume relay work and retain its window.

Fix and regression proof: exact payload exhaustion now precedes the mempool
query. A fragmented one-byte request disconnects, clears block ownership, and
lets a healthy peer take the full window. The focused case and complete
`block_download_tests` group pass 79/79 after incremental build; idle
scheduling measured 0.0242 seconds for 125 peers and 0.1553 seconds for 750
peers over existing 1,000 rounds. No performance claim is made. `git diff
--check` passes. ASan/UBSan remains unrun to preserve the 10 GB reserve (11 GB
free).

Consensus impact: NONE. This is P2P request framing only; chain history,
consensus serialization, PoW, monetary policy, upgrades, block/transaction
validity, and cryptography are unchanged. Worldstream's latest C23
`origin/main` remains `8ef06fa6b276aab0318a097a8b711c91718b90fa`, with no
overlap.
