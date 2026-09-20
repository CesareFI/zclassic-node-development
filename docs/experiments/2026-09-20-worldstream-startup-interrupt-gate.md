<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fresh-sync startup-interrupt gate

The standalone fresh-sync observer retries interrupted child-status waits
without adding a polling sleep. Its hermetic regression existed and the
aggregate benchmark self-test reached it through
`bench_fresh_sync_startup_selftest.sh`, but the production benchmark build
entry did not. That left a direct `make bench_fresh_sync` build vulnerable to
an unqualified regression that could add observer delay or misclassify a live
IBD child after a signal.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`ad45162b3b80df23887d878945f54a4e33cb7ab9`.
`make -n bench_fresh_sync` contained zero invocations of
`bench_fresh_sync_startup_interrupt_selftest.sh`. The aggregate self-test's
Make recipe also contains no direct invocation because its existing coverage
is nested inside `bench_fresh_sync_startup_selftest.sh`.

The new focused Make target wires the existing fixture into the production
benchmark build entry without duplicating its existing aggregate-suite run.
It is classified with the standalone benchmark goals, so a fresh checkout
does not bootstrap unrelated vendor archives before running the fixture.
The fixture extracts the production startup helpers, uses a deterministic
clock and private temporary files, and never starts a node or contacts a peer.
Its 12 cases cover zero through three interrupted waits for each of a live
child, an exited child, and a wait error. Signals add no simulated time or
polling sleep; child exit and wait errors still refuse startup.

Reproduce the focused proof and compiler analysis with:

```sh
make bench-fresh-sync-startup-interrupt-selftest
bash tools/scripts/bench_fresh_sync_startup_interrupt_selftest.sh --analyze
```

On this Linux host the focused Make target passed all 12 cases in 7.53 wall
seconds (5.55 user, 2.15 system), including Make's prerequisite checks. The
compiler analyzer passed in 0.46 wall seconds, the aggregate fresh-sync suite
passed in 36.77 wall seconds, and the actual `make bench_fresh_sync` build
entry passed in 10.92 wall seconds. A dry run
shows exactly one direct interrupt-regression invocation from the build entry;
the aggregate suite continues to reach exactly one nested run through its
startup self-test. Markdown links, test registration, the secret scan, the
no-Python gate, the untracked-source gate, and the core seal/root mirror also
pass.

`make lint-fast` passed 30 of 32 gates, including architecture, flag-registry,
complexity, allocation, pipefail and the Windows platform seam. Its two
failures are environment-only: the environment exposes `.agents` and `.codex`
as ignored root entries, and the Windows guard cannot create scratch beneath
the read-only `/root/.local`.
`check-doc-claims` passes all 152 bound claims across 592 tracked documents.
The inline-path check separately reports a missing path in the 2026-09-19
Worldstream readiness note. That file is not changed here.

This is benchmark qualification, not a claim of faster end-to-end IBD. It
changes no node, validation, consensus, peer scheduling, database, wallet, or
optional-acceleration behavior.
