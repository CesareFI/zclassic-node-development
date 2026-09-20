<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reduce tip-observer row decoding overhead

The tip-agreement recorder decoded each flat SQL response with four `sed`
processes and one `awk` process. Its observation loop uses this reader for
clusters, usable-peer counts and address groups. Combining row formatting
into the existing `awk` stage reduces external parsers from five to two per
response while retaining the original envelope extraction and row bytes.

This slice changes only `sql_rows`, registers its hermetic regression in
`tip-agreement-selftest`, and updates three shifted flag-catalog source-line
pointers. Existing dirty work is excluded from the slice.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with pre-existing working changes.
The pre-slice recorder's SHA-256 is
`67f7f1b5b8a2f5c7e696bfda7af335803ba8dbbe82e5b4cb8ec5962bcf2ac995`.
Linux x86_64, Bash 5.2.21, warm host caches, synthetic 64-row response,
300 decoder calls per run:

| Measurement | Before | After |
|---|---:|---:|
| External parsers per decode | 5 | 2 |
| Wall seconds, run 1 | 1.541 | 1.233 |
| Wall seconds, run 2 | 1.499 | 1.184 |
| Wall seconds, run 3 | 1.547 | 1.264 |
| Median wall seconds | 1.541 | 1.233 |

Median decoder time fell about 20%. This measures observer overhead only;
it does not establish end-to-end IBD or live time-to-tip improvement. No node,
production datadir, peer or network connection participates in the benchmark.

Reproduce the regression and informational benchmark:

```bash
bash tools/scripts/tip_agreement_rows_selftest.sh --bench
```

An optional final argument selects an older recorder. The pre-slice file is
retained locally at `/tmp/worldstream-tip-rows/probe-before.sh`; its run fails
the new two-parser budget after reporting all three timings. The regression
compares exact bytes against the previous decoder on 14 cases, including
empty responses, missing envelope fields, multiple envelopes, whitespace,
IPv6 addresses, wide integers and 10,000 rows. It separately checks the final
newline and upstream failure propagation under `pipefail`. A mutation that
omits output newlines fails the regression. Timing is not a pass threshold.

Validation passed:

- Focused decoder regression and benchmark; original decoder fails process budget.
- Full `test_tip_agreement_evidence.sh` recorder/judge/observer acceptance.
- `tip_agreement_parser_selftest.sh` (452 comparisons).
- Bash syntax, pipefail-status, discarded-status, shell-host-assumptions and
  architecture-tree checks; `git diff --check`.

`make tip-agreement-selftest` and `make lint-fast` each exceeded a 60-second
bound during preparation; their completion is not claimed. The acceptance
scripts were then run directly. The direct flag-registry gate reports 27
stale pointers outside this slice; the three pointers shifted by this edit
were updated. ShellCheck and the public navigator binary are unavailable.
No C implementation changed, and no full node build or live-sync acceptance
was performed.

Consensus, cryptographic validation, optional acceleration and Hetzner-owned
scheduling/database/runtime behavior are unchanged. The reviewed slice has
no credentials, production data, logs, binaries, caches or generated build
output. The pre-existing staged and unstaged work remains intact.

Publication is blocked: `.git` is read-only (`git fetch` cannot write
`FETCH_HEAD`), and origin cannot resolve `github.com`. No commit, push or
remote-SHA verification is claimed. The run-specific patch is retained at
`/tmp/worldstream-tip-rows/slice.patch` for review and later publication.
