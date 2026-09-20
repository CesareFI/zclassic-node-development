<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound recovery benchmark diagnostic RPCs

The recovery stopwatch runs three synchronous diagnostic CLI calls before
writing a non-PASS artifact. None had a timeout, so a hung client could prevent
the benchmark from reporting its result indefinitely. Each call now requests
termination after 20 seconds, followed by forced termination after a one-second
grace. Failed or timed-out calls retain the existing incomplete-bundle flag;
successful output, busy-frontier classification and local-log fallback remain
unchanged. This bounds the CLI waits, subject to OS scheduling; local file I/O
and the benchmark's ordinary sampling RPCs are outside this slice.

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.
The pre-slice script SHA-256 is
`700c25fa0f2d98cb30dc6d3b96ceb10f2434feea4af81baeeb73077bcfad3bfc`;
the changed script is
`f9118b90fcdecf9008fd9c2b3264eb85e3415f041e8e7f46bc777127ce3b7839`.
This working tree already contains pending changes: HEAD alone does not
reproduce the baseline. The saved source and incremental patch are under
`/tmp/worldstream-diagnostic-budget/`.

## Reproduction

```bash
bash tools/scripts/netdisrupt_bundle_budget_selftest.sh [source.sh]
bash tools/scripts/network_disruption_recovery_stopwatch.sh --selftest
bash tools/scripts/netdisrupt_stopwatch_timing_selftest.sh
```

The fixture extracts the production capture function and uses an isolated
mock CLI. It shortens only the 20-second deadline to 100 ms, retaining the real
one-second kill grace. Each stalled mock ignores TERM and waits two seconds
before writing a marker. Marker absence proves forced termination; elapsed
time is informational, not a scheduling-sensitive assertion. All three calls
must pass through the deadline. No node, network or production state is used.

Linux x86_64, Bash and GNU timeout, single local fixture run:

| Capture | Baseline ms | Candidate ms | Candidate result |
|---|---:|---:|---|
| Successful | 20 | 27 | Complete; exact bytes retained |
| Busy frontier | 22 | 25 | Complete; busy flag retained |
| Nonzero CLI exit | 15 | 21 | Incomplete |
| Failed RPCs with local log | 18 | 23 | Incomplete; local log retained |
| Three TERM-resistant CLI calls | 6031 | 3313 | Incomplete; no post-deadline markers |

The baseline fails seven assertions; the candidate passes, including the
missing-executable case. These measurements establish bounded benchmark
reporting behavior, not an end-to-end IBD or time-to-tip speedup. Each successful
call pays the small additional timeout-process cost.

## Validation and publication limits

The recovery stopwatch selftest and all six timing scenarios pass. The height,
record-escaping and tip-readability fixtures pass. Shell syntax, discarded-status,
pipefail-status, shell-host-assumption, architecture, consensus-parity and
core-seal-mirror checks pass. All 554 sealed files and 80 core sections match.
Repository
shell scans cover tracked files; the new fixture also receives explicit syntax
checking and execution. No compiled source changes; ShellCheck is unavailable.

`make z23` encounters read-only Git configuration while initializing Tor and
is stopped by its 45-second bound. `make lint-fast` exceeds a 50-second bound
during preparation. Neither full build nor aggregate lint is claimed green.
No live synchronization or public-node acceptance is claimed.

Only the reporting script, its new fixture, and this report belong to this
slice. Consensus, validation, optional acceleration policy, custody, and
Hetzner-owned runtime/scheduling/database code are unchanged. The existing
index remains byte-identical. No secrets, logs, binaries, caches, production
datadirs or generated output belong to the patch. `git diff --check` passes;
the incremental diff is inspected separately from earlier pending work.

Publication is blocked: `.git` is read-only (fetch cannot create `FETCH_HEAD`)
and GitHub DNS resolution fails. No commit, push, fresh upstream integration,
or remote-SHA equality is claimed. Do not stage the entire already-modified
reporting script as this slice.
