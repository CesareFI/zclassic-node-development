<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound explorer wallet polling during IBD

Branch: `agent/worldstream-ibd-20260918`; baseline HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

## Bottleneck and baseline

The self-contained `/wallet` page started a new `/api/wallet` fetch every
three seconds regardless of document visibility or whether the preceding
request had settled. During IBD, a response slower than the polling interval
therefore accumulated concurrent requests. A request that never settled made
the number of outstanding requests grow without a bound, and a hidden tab
continued generating presentation-only work.

This is GUI observer interference during IBD. It is separate from peer and
block-request scheduling, stalled-request recovery, timeout/reassignment,
database tuning, and core node runtime reliability.

## Change and measurable bound

The page now admits at most one wallet fetch at a time and starts another only
after the current promise settles. It performs no interval fetch while the
document is hidden and refreshes immediately when the document becomes
visible. The visible, responsive three-second cadence is unchanged.

The resulting request bound is one outstanding `/api/wallet` fetch per page,
instead of an unbounded count when a request hangs. Hidden-tab interval work
falls from one attempted fetch every three seconds to zero.

The registered explorer regression renders the production page and requires
the in-flight guard, settlement release, visibility listener, foreground
refresh, and existing three-second cadence. A direct linked render probe was
also run against baseline and candidate source: the baseline failed with exit
1 because all guard markers were absent; the candidate passed with exit 0.

## Validation scope

- Strict C23 compile of the production view: PASS with `-Wall -Wextra
  -Werror -pedantic` and the repository development include profile.
- GCC `-fanalyzer` compile of the production view: PASS.
- Strict C23 syntax compile of the changed registered-test translation unit
  with `ZCL_TESTING`: PASS.
- Direct linked baseline/candidate render mutation probe: expected 1/0 exits.
- `make -j"$(getconf _NPROCESSORS_ONLN)" t-fast ONLY=explorer`: PASS,
  3/3 selected groups, zero skips. This includes the production page render
  regression in `test_explorer` plus `test_explorer_rpc_call` and
  `test_explorer_index`.
- Architecture tree, file-purpose ratchet, controller-private-header boundary,
  pure-consensus include boundary, consensus-parity, sealed-core manifest, and
  hot-swap core-root mirror gates: PASS.
- `make lint-fast`: 28/32 gates passed. The four failures are outside this
  slice: environment-owned `.agents`/`.codex` root entries, unrelated dirty
  benchmark/tool complexity and flag-registry findings, and a sandbox-denied
  Windows acceptance scratch directory under `/root/.local/state`. After the
  polling regression was extracted into its own helper, the complexity gate
  no longer names `test_explorer`.

The slice changes only the explorer wallet HTML/JavaScript renderer, its
registered render regression, and this evidence record. It does not touch
chain state, validation, proof of work, monetary or difficulty rules,
activation heights, consensus serialization, cryptographic semantics,
optional acceleration policy, peer scheduling, or storage. Independent
Zclassic validation remains authoritative.
