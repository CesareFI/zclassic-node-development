<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: defer legacy wallet refresh during IBD

Branch: `agent/worldstream-ibd-20260918`; baseline HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

## Bottleneck and baseline

The wallet dashboard and its pulse endpoint ran
`wv_sync_wallet_from_zclassicd()` synchronously on their request thread even
while the node was downloading or connecting the chain. One refresh performs
two list RPCs (`listunspent` and `z_listunspent`) and can then perform one
`gettransaction` RPC for each of 50 unconfirmed transaction rows. The measured
work bound in the baseline request path is therefore 52 sequential RPCs per
refresh. The baseline dashboard called this path whenever legacy sync was
enabled; a dirty pulse did the same without consulting sync state.

The command-center request path also executed `count(*)` and `SUM(value)`
across the changing `utxos` table on every render.  Those are two
presentation-only O(UTXO) aggregates during active IBD, when their transient
answers are least useful.

This is both GUI latency and observer interference during IBD. It is separate
from peer scheduling, block-request scheduling, stalled-request recovery,
timeouts, LevelDB tuning and core runtime reliability.

## Change

Automatic dashboard refresh is now allowed only in `SYNC_IDLE` and
`SYNC_AT_TIP`. Every active-sync, recovery, snapshot and failed state defers
the legacy mirror, so the IBD request-path bound becomes zero legacy wallet
RPCs. Explicit send and shield refresh paths remain unchanged. Once the node
returns to idle or reaches tip, the retained dirty flag triggers the existing
refresh behavior. A deferred pulse also avoids repeatedly recomputing unchanged
wallet data at the same height. Browser polling schedules its successor only
after the current request settles, so a slow IBD-time pulse cannot accumulate
overlapping requests.

The command center now skips both whole-UTXO aggregates while peers, headers,
blocks, connected blocks, or a snapshot are advancing and labels their values
`Deferred`.  Outside active IBD it retains the existing exact totals and units.

The focused regression enumerates every sync-state value, the two allowed
states and the disabled flag. Its observable baseline/candidate is 52/0
possible sequential legacy RPCs per automatic IBD refresh. A mutation restoring
the old `return enabled` policy fails the regression.

## Validation scope

The focused `wallet_view` registered test exercises the policy, serialized
polling, command-center IBD rendering, and the existing dashboard render-time
checks. The broader wallet dashboard story and ordinary lint/build gates cover
integration. The exact slice is limited to the wallet-view internal
declaration, dashboard/pulse and command-center call sites, their templates and
focused regressions, and this record.

No chain data, production datadir or wallet participates in the test. No
consensus predicate, serialization, proof, cryptographic validation, monetary
rule or optional Z23 acceleration policy changes. Independent Zclassic
validation remains authoritative.

## Results

- C23 syntax/diagnostic compile of the changed controller and registered-test
  translation units: PASS with `-Wall -Wextra -Werror -pedantic`.
- GCC `-fanalyzer` compile of the changed controller: PASS.
- Standalone linked policy regression across `0..SYNC_NUM_STATES`, including
  retained-dirty catch-up behavior: PASS.
- Mutation restoring the baseline unconditional policy: correctly FAILS.
- Relevant direct lint gates: PASS (controller-private headers, pure-consensus
  include boundary, consensus parity, and hot-swap sealed-core-root mirror).
- Architecture tree: PASS (five authorities, six contexts, 63 single-owner
  modules).
- File-purpose ratchet: PASS (4,302 source files, zero new violations).
- Controller-private-header and pure-consensus include-boundary gates: PASS.
- Consensus parity, sealed-core manifest (554 files/80 sections), and
  hot-swap core-root mirror checks: PASS.

A repeat of the whole-tree complexity ratchet was blocked by six unrelated
pre-existing Worldstream worktree changes in `tools/bench_fresh_sync.c`,
`tools/fs_handshake_probe.c`, and `tools/snapshot_from_coinskv.c`; none is in
this slice, and the gate named no wallet-view function. The focused compile,
analyzer, linked policy regression, and relevant boundary gates above pass on
the exact files in this slice.

`make t-fast ONLY=wallet_view` selected the two registered wallet-view groups,
but this isolated checkout lacks the pinned third-party archives and the
sandbox cannot resolve their upstream hosts. The attempt therefore stopped in
vendor bootstrap before linking or executing either group. The registered
group is not claimed as run; the direct C23 compile, linked regression and
mutation proof above cover the changed policy without weakening an assertion.

A later repeat again selected exactly `test_wallet_view` and
`test_wallet_view_port` and generated byte-identical templates, but timed out
waiting for the pre-existing `vendor/.build.lock` before test execution. The
shared lock was preserved rather than removed. That repeat is likewise not
claimed as a pass. Direct invocation of the already-built repository gate
binaries reconfirmed the architecture, private-header, seal-mirror,
file-purpose, credential-scan and warning-suppression results above.

The final attempt used the vendor builder's supported isolated lock override
instead of disturbing that shared lock.  It again selected exactly the two
wallet-view groups, then proved the actual remaining blocker: pinned zlib,
OpenSSL and SQLite archives are absent and this sandbox cannot resolve their
upstream hosts.  Before bootstrap stopped the gate, both changed production
controllers compiled successfully under the repository's full dev profile.
An independent C23 `-Werror -pedantic` syntax sweep covered all six changed C
translation units, and GCC `-fanalyzer` covered both controllers; both passed.
