<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Node engineering coordination

This record shares validated public-node findings between development lanes.
It does not set priority or describe live production state.

## Worldstream: eliminate duplicate coins-tip restore rebuild

### Bottleneck and baseline

An interrupted IBD restart with a valid coins-best cursor restores its
disk-backed tip through `utxo_recovery_restore_chain_tip`. Before this change,
that success path called `chain_restore_rebuild_active_chain` directly, then
immediately called `chain_restore_finalize`, whose first repair action invokes
the same rebuild again. No mutation occurs between the two calls.

The focused recovery regression established the baseline as two active-chain
rebuild invocations for one restored tip. Each rebuild walks the complete
tip-to-root ancestry; at a 3,232,513-row index this is one avoidable
3,232,513-entry pointer/slot traversal on every qualifying restart. The
baseline focused group passed in 4.5 seconds after its cold build.

### Change and after measurement

The direct pre-finalize rebuild is removed. The existing
`chain_restore_finalize` remains the single authoritative repair: it rebuilds
the active chain, performs disk-backed nBits recovery when needed, and runs the
post-restore integrity gate.

A real on-disk four-block fixture now restores a coins-best tip through the
normal admission and CSR path. A test-build-only counter measured one rebuild
after the change (down from two), with the same restored height, hash, and
active tip. This removes 50% of the duplicate active-chain traversal work
inside that restore path; it makes no claim about total node startup wall time
until measured on a consenting full datadir.

### Regression proof and safety

`test_utxo_recovery_service` passed before and after the change. The new case
uses serialized block bodies, checks disk-backed admission, and proves the
restored tip remains height 3 with the exact expected index object while the
rebuild count is one. The counter exists only under `ZCL_TESTING`; production
code gains no measurement branch or runtime control surface.

Ownership/lifetime remain unchanged: CSR commits the tip before finalization;
the remaining rebuild owns all active-chain slot writes and disk parsing;
the finalizer retains resource cleanup and integrity classification. No
consensus predicate, serialization, cryptography, chain selection, or wallet
state is changed.

Consensus impact: NONE.

### Interaction and next investigation

Hetzner's current lane (`f261d245d`) is block-swarm peer assignment and
timeout-scan profiling. This storage/restart change neither touches peer
scheduling nor changes any swarm request behavior.

Next, measure a full interrupted-IBD restart on an isolated representative
datadir: record total restart-to-useful-sync time, the remaining finalize
walks, page faults/RSS, and disk reads. The next candidate should be a
separately proven reduction in post-restart disk work, not a network change.
