<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: restore client-tip observation in repeat IBD benchmarks

The repeat-run C3 driver searched `/tmp/zcl-c3-stopwatch.*`, while the
single-run stopwatch creates its client under `ZCL_CS_ROOT` or the private
`$HOME/.local/state/zclassic23/scratch/coldstart` parent. With the default
layout, the driver could spend every run's budget without ever reading the
client tip hash. Unrelated directories under the global glob could also
consume RPC attempts. This blocked hash-confirmed repeatability measurement;
it was not evidence of a slow or invalid node.

The driver now creates a private containing directory for each run under the
same configured scratch parent, passes that directory to the stopwatch, and
polls only its cookie-bearing child. The cookie excludes the isolated HOME
sibling and avoids RPC attempts before credentials exist. The stopwatch still
owns client cleanup. The driver stops its poller and removes only its empty
containing directory, reporting and preserving unexpected residue.

## Baseline and bounded witness

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The original checkout contained substantial
staged and unstaged work, including an independent scalar-parser change in
the driver. Both clean HEAD and the working driver at entry failed the same
new regression. The isolated candidate contains only this scratch-discovery
change, its regression, and this report; it does not include that parser edit.

Linux x86_64, Bash 5.2. The fixture runs the actual driver with a mock
stopwatch and RPC executable, two sequential runs, and a shortened polling
sleep. No node, network, chain, production datadir, or real credentials are
used. Each mock client reports height 100 and the same fixed hash as the
mock peer. The harness waits for an actual trace row, with a bounded wait.

| Observation | Before | After |
|---|---:|---:|
| Successful mock runs | 2 | 2 |
| Distinct clients observed under the default scratch root | 0 | 2 |
| Repeat benchmark exit | 1 (client tip never read) | 0 |

The custom-root case also observes both clients, including a path containing
spaces and glob characters. Unrelated cookie-bearing directories are never
queried. A client without a cookie generates zero client RPC attempts and
still fails hash confirmation. A non-passing harness remains non-passing even
when hashes agree. An absent scratch parent refuses before launching either
client. Normal runs remove their containing directories; residual files are
preserved and reported. Removing the cookie check makes the test fail because
the poller queries both clients and both HOME siblings (four paths, not two).

These counts establish measurement coverage and bounded discovery scope,
not an end-to-end IBD or time-to-tip speedup. Poll cadence, RPC deadline,
tip agreement checks, and acceptance thresholds are unchanged.

## Reproduction and validation

```sh
bash tools/scripts/c3_stopwatch_scratch_selftest.sh
bash tools/scripts/c3_stopwatch_triple_run.sh --selftest
```

The focused test accepts an optional older driver path. It is also invoked
by the existing driver selftest, which the repeat-run Make target already
requires. Both the working tree and isolated candidate pass that suite.
Bash syntax, architecture-tree, shell-host-assumption, pipefail-status-pipe,
and whitespace checks pass. The port-probe and isolated-readiness selftests
pass (the latter uses the existing `jsonq` helper binary). The broader
clean-HEAD peer-tip selftest fails at its existing height-zero case; that
helper is outside this slice. Full `lint-fast` did not finish within a
50-second bound, with prerequisite template generation and missing Tor
archives reported, and is not claimed green. No compiled source is changed.
The consensus seal independently verifies all 554 files and 80 sections.

Consensus, validation semantics, optional acceleration policy, legacy peer
and block-request scheduling, database tuning, and node runtime are unchanged.
Only the driver, test source, and this report belong in the commit. Fixtures,
logs, credentials, generated files, and binaries are excluded.

The isolated candidate is prepared under
`/tmp/z23-worldstream-scratch-slice.V2M2Dw` on the required development branch,
preserving the original checkout's index and unrelated edits. Publication is
blocked by unavailable GitHub DNS; remote SHA equality remains unverified.
The next useful measurement is a real repeat IBD run against an explicitly
authorized fixture peer, now with client-tip observations bound to each run.
