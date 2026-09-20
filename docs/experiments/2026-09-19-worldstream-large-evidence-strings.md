<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream large evidence string cost

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The baseline is the pre-slice working-tree evidence library, including earlier
uncommitted Worldstream improvements. Its SHA-256 is
`686e23df8fd254c617f0af0fe157b6d20d3a0c88a4aa63f00d2a233a9e955288`.
This slice extends that existing work; it does not claim those improvements
have been committed. Unrelated staged and unstaged work remains intact.

The shared evidence serializer serves sync SLO, tip-agreement and explorer
observers. Bash substitutions make short fields inexpensive, but dense escapes
in a large diagnostic repeatedly copy the string. A synthetic 32,768-byte
quote-only field reproduces the cost without any node, network or datadir.
Fields longer than 4,096 characters now use the original streaming tr/sed
transformation. Short fields retain their zero-external-tool path. The fallback
captures output before emission, preserving exact bytes even when a platform's
sed adds a final newline. Raw newline, CR and tab normalization is unchanged.

Measurements: AMD EPYC 7402P, Linux x86_64, Bash 5.2.21, warm ordinary filesystem caches,
uncontrolled ambient load. Three calls of the real `evidence_jstr` function,
each with the same synthetic field:

| Locale | Before wall seconds | After wall seconds | Median before / after |
|---|---|---|---|
| C.utf8 | 0.698, 0.697, 0.677 | 0.014, 0.019, 0.013 | 0.697 / 0.014 |
| C | 0.025, 0.020, 0.017 | 0.014, 0.014, 0.015 | 0.020 / 0.014 |

The UTF-8 median removes about 683 ms from this synthetic serialization.
This is an observer microbenchmark, not measured production payload frequency,
end-to-end IBD acceleration or time-to-tip improvement. Locale materially
affects the baseline, so the test supports both explicitly. Wall times are
informational; byte equivalence and size-based routing are deterministic gates.

Reproduction (save the pre-change library separately for the baseline):

```bash
LC_ALL=C.utf8 bash tools/scripts/evidence_large_string_selftest.sh --bench --baseline /tmp/before.sh
LC_ALL=C.utf8 bash tools/scripts/evidence_large_string_selftest.sh --bench
LC_ALL=C bash tools/scripts/evidence_large_string_selftest.sh --bench
```

The regression compares complete string literals against the previous
transformation. It covers 4,095/4,096/4,097-character boundaries, large plain
and quote-dense fields, all non-NUL bytes, trailing whitespace, backslashes,
and large valid UTF-8 strings. The baseline passes byte equivalence in
baseline mode and fails the new routing gate at 4,097 bytes in normal mode.
Both C and C.utf8 pass the changed regression.

Validation:

- All evidence-selftest constituents pass when invoked directly with their
  supported arguments, including intervention, explorer, parser and reader
  fixtures. The full tip-agreement recorder/judge/observer suite passes.
- Bash syntax, architecture-tree, pipefail-status, discarded-status,
  shell-host-assumption and `git diff --check` checks pass. Tracked-tree lint
  does not scan the new untracked regression; its syntax and execution pass
  separately. No compiled node code changes in this slice.
- `make evidence-selftest` and `make lint` each hit a 50-second bound during
  setup, after template checks and the missing Tor archives warning. Neither
  aggregate is claimed green. No threshold or assertion was weakened.

The exact owned delta is nine added library lines, one evidence-selftest Make
entry, the new large-string regression, and this note. Review shared files
against the pre-slice working tree. Changed library SHA-256:
`2a0ba6005c5340a8639463a9817b4fd4721caebecf2b58c26d6400c8c1dea3fa`.
No wallets, keys, credentials, logs, caches, binaries, build directories or
temporary benchmark output belong to the slice. Core and reducer files match
HEAD; validation semantics, optional acceleration, peer scheduling, databases
and node runtime are unchanged.

Publication is incomplete. Fetch fails because `.git/FETCH_HEAD` is on a
read-only filesystem; origin queries fail because GitHub DNS is unavailable.
No commit, push or exact remote-SHA verification is claimed. The checkout
remains on the required development branch. Publishing still requires working
Git metadata and origin access, separating prior work, and completing the
remaining aggregate gates.
