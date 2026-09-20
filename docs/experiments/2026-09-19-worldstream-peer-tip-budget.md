<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound reference-tip capture before cold-start trials

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, Linux x86_64,
Bash 5.2.21. The checkout already contains extensive unrelated staged and
unstaged work. This slice changes only reference-tip capture and its selftest
in `tools/scripts/cold_start_to_tip_probe.sh`, adds
`tools/scripts/cold_start_peer_tip_selftest.sh`, updates the two affected
source-line references in `engine/composition/flags.def`, and adds this note.

The preflight `getblockcount` runs before the trial clock starts. Unlike the
in-trial sampling RPC, it had no timeout. Also, command substitution retained
tip-looking stdout after a nonzero RPC exit, and the following numeric checks
accepted that output. Neither defect requires a node to reproduce.

The new fixture executes the actual reference-capture block with a local RPC
double. It checks the command, datadir and port arguments, and uses real
`timeout` processes. The two stalled doubles sleep for 30 seconds; one ignores
TERM. An outer eight-second watchdog bounds each regression run.

| Observation | Before | After |
|---|---|---|
| Valid successful tip | Accepted | Same tip accepted |
| Valid-looking tip, RPC exit 1 | Accepted incorrectly | Named skip, exit 2 |
| Stalled RPC | Outer watchdog exit 124 | Named skip, exit 2 |
| RPC ignores TERM | Outer watchdog exit 124 | Named skip, exit 2 |
| Empty, malformed, low or negative tip | Refused | Refused |

Reference capture now has a five-second timeout and a one-second forced-kill
grace. Failure is checked before height extraction. Existing height parsing,
the minimum reference height and the measured trial budget remain unchanged.
These results establish bounded benchmark preflight and failed-observation
rejection, not a measured reduction in chain IBD time. No network, live node,
production datadir, or wallet was used.

Reproduce:

```sh
bash tools/scripts/cold_start_peer_tip_selftest.sh
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
```

The first command optionally takes an older probe path. The original probe
fails three of eight cases. The corrected probe passes all eight. The full
probe selftest passes in the working tree and in a temporary source fixture
containing committed source plus only this slice. Shell syntax, discarded
status, pipefail status-pipe, shell-host-assumption, architecture, and
`git diff --check` checks pass. ShellCheck is unavailable; no compiled behavior
changes, so no compiler or chain-validation performance claim is made.

`make lint-fast` and `make check-architecture-tree` remained in prerequisite
preparation and were interrupted. The direct lint driver completed the fast
gate set with four failures: existing `.agents`/`.codex` root entries,
complexity violations in the previously modified fresh-sync/handshake tools,
unrelated flag-source pointers, and an unwritable Windows selftest scratch
directory. The affected probe's two flag pointers were refreshed and no longer
appear in that gate's failures. No thresholds or baselines were weakened.

Consensus, independent validation, optional Z23 acceleration, peer scheduling,
database tuning and node runtime behavior are unchanged. Publication remains
unverified: fetching the development branch failed on read-only
`.git/FETCH_HEAD`, and querying origin failed because GitHub DNS was unavailable.
Preparing an isolated Git index for just these four files also failed when
Git tried to create the probe's object in the read-only object store. No commit
or push was completed; the existing staged work was not committed with this
slice. The isolated committed-source delta is retained for this session at
`/tmp/worldstream-peer-tip-head.patch`; it is temporary development output,
not a repository artifact or publication receipt.
The required branch remains `agent/worldstream-ibd-20260918`.
