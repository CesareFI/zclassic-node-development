<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream C3 tip observation cost

Scope: `tip_h_hash` in `tools/scripts/c3_stopwatch_triple_run.sh`, the
read-only tip observer used by repeated fresh-sync benchmarks. Node runtime,
peer/request scheduling, databases, consensus, and validation are unchanged.
Optional acceleration and independent validation authority are unchanged.

Baseline source: `c1f7863d098e1efaa8deba240c580ae0559312a5`.
This checkout also contains earlier uncommitted scalar-parser improvements;
they were inspected and measured separately, and are not part of this slice.
Even with that parser, each successful tip decode starts three child shells
to extract `ok`, `height`, and `hash`. The change decodes those scalars in
the calling shell, preserving unreadable-tip sentinels and integer text.

On Linux x86_64 with 48 available logical CPUs and Bash 5.2.21, three warm trials
of 200 synthetic tip decodes gave these wall seconds:

| Decoder | Trial 1 | Trial 2 | Trial 3 | Median | Child shells/sample |
|---|---:|---:|---:|---:|---:|
| Committed baseline | 2.888 | 2.867 | 2.931 | 2.888 | 3 |
| Existing uncommitted builtin scalar parser | 0.772 | 0.767 | 0.761 | 0.767 | 3 |
| This change | 0.051 | 0.031 | 0.033 | 0.033 | 0 |

The input is one in-memory compact tip document; there is no node, RPC,
datadir, network traffic, or chain cache in the fixture. Timings include
shell loop and output-redirection overhead. Host load was not controlled.
This measures observer overhead only, not end-to-end IBD or time-to-tip.
The original decoder also invokes external parsing programs; the child-shell
count is not a census of all external processes.

Reproduce from the repository root:

```sh
bash tools/scripts/c3_stopwatch_tip_decode_selftest.sh
bash tools/scripts/c3_stopwatch_triple_run.sh --selftest
```

The fixture accepts `--baseline /path/to/prior-driver.sh` to report the old
cost. Without `--baseline`, the prior decoder fails the zero-child-shell
assertion. Fifteen value fixtures cover compact, reordered, multiline,
quoted, wide-integer, duplicate, missing, false, negative, and decimal
fields. The changed decoder also works with external programs unavailable.
Timing is reported, never used as a flaky acceptance threshold. The new
fixture is included in the driver's existing `--selftest` entry point.

Focused fixtures, the complete driver selftest (also with the pre-existing
scratch-isolation and RPC-timeout fixtures), syntax checking of all 501
tracked shell scripts, and `git diff --check` pass. The discarded-status,
pipefail-status-pipe, shell-host-assumptions, and bare-tmp-fixture checks
pass, as does `make check-architecture-tree`.

Full `make lint` was attempted, but remains unqualified. A first attempt
lost its compile-authority generation; the fresh attempt could not fetch
zlib because GitHub DNS resolution failed, and the remaining build was
interrupted. Clang and ShellCheck are unavailable. Branch fetches also
failed on DNS. No full-node acceptance, full lint pass, remote publication,
or reduction in time-to-tip is established by these results.
