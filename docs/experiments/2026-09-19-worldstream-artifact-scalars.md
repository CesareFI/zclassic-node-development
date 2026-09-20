<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stopwatch artifact scalar reader

Scope: C3 benchmark artifact comparison only. No node, peer scheduler,
database, wallet, validation, consensus, or acceleration policy changed.
This measures evidence-processing cost, not end-to-end IBD improvement.

## Baseline and witness

The starting branch was `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with extensive staged and
unstaged work already present. The pre-edit checker SHA-256 was
`b2593942114f892a888d3875b8f45981020254a755a2e6e64934384736f36122`.
Existing sample-presence changes in that checker were preserved.

`pj_scalar` launched grep, head, and sed for every scalar read. With 100,000
matching artifact records it printed the correct first value but returned
status 2 on this host when the downstream reader closed the pipeline.
The new regression fails against that pre-edit reader.

One awk process now extracts the same first matching scalar and exits after
that record. Missing keys/files still fail; empty strings remain successful
empty values. The existing fixed-emitter parsing policy is retained, including
undecoded escapes, numeric prefixes and nested-field matches. This is not a
general JSON parser or a stronger artifact-validity claim.

## Measurement

Linux 6.8.0-139-generic, x86_64, 48 exposed logical CPUs; Bash 5.2.21,
GNU Awk 5.2.1. Local synthetic files, warm filesystem caches, no node or
network. Three trials per shape, 200 reads per trial. Other Make validation
commands were outstanding, so wall times describe this session rather than
an isolated host performance qualification.

| Input | Before wall seconds | After wall seconds | Before CPU seconds | After CPU seconds |
|---|---|---|---|---|
| One record | 0.696 / 0.665 / 0.653 | 0.725 / 0.710 / 0.714 | 1.467 / 1.446 / 1.460 | 0.754 / 0.738 / 0.741 |
| 100,000 records | 0.816 / 0.802 / 0.806 | 0.723 / 0.725 / 0.726 | 1.828 / 1.814 / 1.810 | 0.753 / 0.755 / 0.756 |

CPU is summed user plus system time, including pipeline children. The change
reduces tools per read from three to one and roughly halves CPU cost here.
Small-file wall latency increased; large-file wall latency decreased. No
time-to-tip speedup is inferred. Deterministic gates assert process count,
successful first-match status and no later record processing, not wall time.

Reproduce with the saved pre-edit checker or any specified candidate:

```sh
bash tools/scripts/stopwatch_scalar_selftest.sh --baseline --bench /path/to/before.sh
bash tools/scripts/stopwatch_scalar_selftest.sh --bench
bash tools/scripts/stopwatch_artifact_symmetry_check.sh --selftest
```

## Validation and integration

- Eighteen differential scalar cases, missing file, large artifact, one-tool
  budget and first-record stop passed with GNU Awk, mawk and BusyBox awk.
- The intact artifact pair passed; all seventeen symmetry mutations failed
  as required. The new regression runs through the existing `--selftest` and
  therefore the existing Make target, without another Makefile modification.
- Shell syntax and `git diff --check` passed. No compiled code changed.
- The adjacent stopwatch string, quote and large-quote regressions passed.
- The standalone pipefail-status-pipeline lint gate passed.
- `make stopwatch-symmetry-selftest` and `make lint-fast` did not reach a
  verdict after several minutes and were interrupted (exit 130). Their last
  output reported absent Tor archives and unchanged generated templates.
  The symmetry suite and its string/quote prerequisites were run directly
  and passed; this does not establish a passing aggregate lint gate.
- All fixtures, timings and the baseline copy stayed under `/tmp`.

Publication is unavailable in this environment: `.git` is read-only and
`git fetch origin main` fails writing `FETCH_HEAD`; read-only `git ls-remote`
also fails because `github.com` cannot resolve. No commit, push or remote-SHA
verification is claimed. Preserve the pre-existing index and commit only this
slice when the environment permits the required integration gates.
