<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound large stopwatch string replacement cost

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The shared stopwatch artifact encoder used Bash replacement for every string.
Dense escapes repeatedly copy the remaining string, making a synthetic 32 KiB
quote field cost about 0.67 seconds in the host's UTF-8 locale. This helper
serializes cold-start and recovery benchmark reasons and other artifact fields.
This is an observer-cost finding, not a measured live-node bottleneck or an
end-to-end IBD/time-to-tip improvement.

`json_escape` now retains Bash replacement through 4096 characters and uses
the existing streaming transformation for larger fields. Newlines become
spaces before sed, so capturing its output preserves meaningful trailing
whitespace even if sed adds a final newline. Quotes, backslashes, tabs and
carriage returns retain their previous encodings. `json_string` now propagates
encoder failure. This follows the existing large-field approach in
`evidence_sources.sh`; its different whitespace contract prevents using that
encoder directly.

The new `stopwatch_large_quote_selftest.sh` is wired into the existing
`stopwatch-quote-selftest` target. It checks both sides of the size boundary,
dense and absent escapes, all non-NUL bytes, UTF-8, trailing whitespace,
short fields without external executables, and an encoder failure.

## Measurement

Linux x86_64, Bash 5.2.21, GNU sed 4.9. Synthetic in-memory 32,768-byte quote
fields, three sequential warm-cache trials per variant/locale, uncontrolled
ambient load. No node, RPC, network or production datadir participates.

| Locale | Baseline wall seconds | Candidate wall seconds |
|---|---|---|
| C | 0.020 / 0.018 / 0.018 | 0.013 / 0.013 / 0.012 |
| C.utf8 | 0.673 / 0.672 / 0.672 | 0.016 / 0.015 / 0.016 |

The UTF-8 median improves about 42 times; the C-locale median improves about
28%. The existing 500-short-field benchmark remains process-free, with
baseline 0.544 / 0.548 / 0.547 seconds and candidate 0.570 / 0.569 / 0.563
seconds in separate runs. These are observations, not timing pass thresholds;
no short-field speedup is claimed. Large fields now require sed and tr.

The baseline is the dirty working library at entry, SHA-256
`22d697042e699ee78b0009177864c88f2c68e8bb01bc8240413f2e420ebcbb0a`,
not pristine HEAD. Existing edits in the library and Makefile are prerequisites
and are not part of this slice. Baselines, raw output, and the isolated slice
patch remain under `/tmp/worldstream-stopwatch-large-quote/`.

## Validation and limits

Passed:

- New large-field self-test in C and C.utf8, and with BusyBox sed/tr.
- Existing stopwatch quote, numeric-reader and busy-response tests; cold-start
  artifact quoting and network-disruption record escaping tests.
- Full isolated `cold_start_to_tip_stopwatch.sh --selftest` and
  `network_disruption_recovery_stopwatch.sh --selftest`.
- Bash syntax, architecture-tree, shell-host-assumption, pipefail-status and
  discarded-status checks. The latter focused gates also ran through the lint
  runner where applicable.
- `git diff --check` and `git diff --cached --check`.

`make lint-fast` and `make stopwatch-quote-selftest` each exceeded a 50-second
bound during Make initialization, before gate/test verdicts. The quote target's
two script recipes passed directly. Aggregate lint is not claimed green.
ShellCheck and the public node binary are unavailable. No C code changed;
compiler and live-chain acceptance are not claimed for this shell-only slice.
Native macOS execution remains unverified.

The exact slice changes only the shared artifact encoder, one test recipe,
the new regression/benchmark script and this record. Consensus files match
HEAD; validation semantics, optional Z23 acceleration policy, and Hetzner's
scheduling/database/runtime surfaces are unchanged. No secrets, node data,
logs, caches, binaries or generated build output belong to the slice.

Publication is incomplete. Fetch cannot write `.git/FETCH_HEAD` because Git
metadata is read-only; the remote branch lookup cannot resolve GitHub. No
commit, push or exact remote-SHA verification occurred. Do not stage the whole
dirty library or Makefile as this slice. Aggregate lint and publication still
need completion in an environment that permits them.
