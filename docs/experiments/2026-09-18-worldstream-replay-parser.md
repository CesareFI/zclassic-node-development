<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream replay-canary integer polling cost

The full-history replay canary launches three external tools (`grep`, `head`,
`grep`) for each integer field read during progress polling and verdict
collection. A Bash regex removes those external processes. The field reader
still selects the first integer match, keeps wide counters as text, preserves
line-local whitespace matching, and returns empty output with success status
on a miss. Existing numeric-prefix handling is unchanged; this is not a
general JSON validator.

This slice changes only `tools/scripts/replay_canary.sh`, adds its standalone
parser regression/benchmark, and records this experiment. The original
implementation started from HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. Other pre-existing staged and unstaged work
is left intact. Baseline canary SHA-256:
`4fae0d0f330f2f0651e95362133d71adcd8b0f6e80030ee87f3bab77e7145fcb`.
Updated canary SHA-256:
`66cc6dc06d21c5a58869da9ebcd759412a81c1e8e08b1e5d741ece53a9a1338e`.

Measured on Linux x86_64 with Bash 5.2.21, three trials of 900 field reads,
using the same command-substitution pattern as the live caller. Host load
was uncontrolled. No node, peer, wallet, or production datadir was used.

| Measurement | Before | After |
|---|---:|---:|
| External parser tools per integer | 3 | 0 |
| Trial 1 wall seconds | 4.651 | 1.249 |
| Trial 2 wall seconds | 4.592 | 1.237 |
| Trial 3 wall seconds | 4.631 | 1.256 |
| Median wall seconds | 4.631 | 1.249 |

The median decreases about 73%. This measures observer overhead only; it
does not establish faster chain validation or reduced time to tip. The
remaining string readers still launch external tools and are a possible
next instrumentation measurement, not a measured dominant IBD bottleneck.

Reproduce from the checkout:

```bash
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/replay_canary.sh > /tmp/worldstream-replay-baseline.sh
bash tools/scripts/replay_canary_parser_selftest.sh --bench /tmp/worldstream-replay-baseline.sh
bash tools/scripts/replay_canary_parser_selftest.sh --bench
```

An optional final argument selects a saved baseline harness. The fixture
loads the integer-reader function for parser checks and timing; verdict
checks invoke only the existing `--self-test` entry point. All 23
output/status checks pass on both implementations, including a 256 KiB
reply. The baseline fails the new deterministic zero-external-tools check,
as intended. A fixture-only mutation forcing reject counts to zero fails
the expected `FAIL/consensus_rejects` verdict check.
Wall-clock timing is informational, not a machine-dependent acceptance bar.

The continuation made the broader verdict check reproducible in the same
selftest, using isolated RPC and binary-identity fixtures. Both old and new
harnesses produced the same expected verdict, reason, and exit code for 13
cases: anchor/genesis passes, rejects, checkpoint hash mismatch, cross-node
height/count/supply mismatches, skipped scripts, both elapsed bounds, failed
validation, timeout, and exact UTXO hash mismatch. This is fixture evidence,
not a full-history replay or consensus acceptance claim. Logging and global
filesystem sync are stubbed only in the fixture child environment; these
checks make no journal-delivery or crash-durability claim.

Bash syntax, artifact-symmetry mutations, shell-host assumptions,
pipefail-status-pipe, discarded-status, no-Python, no-API-key,
no-warning-suppression, architecture, consensus-parity lint, and
`git diff --check` pass. All 554 sealed files and 80 section seals verify
unchanged. No node runtime, validation predicate, replay assertion, acceptance
threshold, optional-acceleration policy, or Hetzner-owned surface changes.
No secrets, binaries, caches, generated artifacts, or temporary benchmark
output belong to this slice.

In this continuation, `make -j2 t-fast ONLY=replay_canary_verdict` reported
that the Tor prerequisite could not register its submodule because
`.git/config` is read-only. Neither that invocation nor `make -j2 lint`
completed; both were interrupted after several minutes without further
output. No registered-suite or full-lint pass is claimed. Focused checks
above do not replace those publication gates.

Publication also remains blocked by read-only `.git` metadata and unavailable
GitHub DNS. Fetching the exact development branch cannot write `FETCH_HEAD`;
`git ls-remote origin refs/heads/agent/worldstream-ibd-20260918` cannot resolve
GitHub. HEAD remains `c1f7863d098e1efaa8deba240c580ae0559312a5` on the required
branch. This continuation preserves the pre-existing index and leaves its
selftest and report additions unstaged. Commit, push, and remote-SHA
verification remain incomplete; no push was attempted.
