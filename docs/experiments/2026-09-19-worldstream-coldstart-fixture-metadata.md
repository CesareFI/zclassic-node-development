<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: cold-start fixture selection metadata

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The cold-start regression gate still launched separate `stat` processes for
each candidate's size and modification time. The related tip probe already
combined these reads. Apply that same small change to `cold_start_test.sh`,
and extend the existing snapshot-selection selftest to exercise its actual
inline selector without launching a node. The existing Make target now runs
both selectors. The Linux/GNU shell-assumption inventory shrinks by one call.

Selection retains the strict greater-than-10-MiB floor, newest timestamp,
last-candidate tie order, epoch-zero eligibility, missing-file handling and
explicit snapshot override. Failed combined metadata reads skip the candidate;
there is no longer a second metadata observation that can fail independently
or observe a different generation. This does not bind the later file copy
against replacement. The existing GNU `stat` requirement is unchanged.

## Baseline and measurement

The baseline is the working script at entry, SHA-256
`1f19d4c50c2ba0ec05d250b014e8c8f0fd876c7aa54d3820845946cfca614895`,
not pristine HEAD. The changed script is
`d4dee05d87c191c10812eedf5cb81bc2c1bd79a2eeb13ea37adee63a5312ca47`.
Linux x86_64, Bash 5.2.21, GNU metadata tools, local sparse fixtures, warm
ordinary filesystem caches, uncontrolled ambient host load. Each run selects
from 100 eligible files ten times and checks the exact winner. Both variants
count actual metadata command invocations. Fixture creation is outside timing.
The first candidate measurement followed the first baseline measurement; two
further baseline/candidate pairs followed. A small isolated selector check
overlapped part of the later measurements.

| Measurement | Baseline | Candidate |
|---|---:|---:|
| Commands per ten selections | 2,000 | 1,000 |
| Wall seconds, run 1 | 7.771 | 4.052 |
| Wall seconds, run 2 | 7.852 | 3.996 |
| Wall seconds, run 3 | 7.664 | 3.930 |
| Median wall seconds | 7.771 | 3.996 |

The synthetic setup median decreases about 49%. Snapshot selection precedes
the node-launch timer. This is observer/setup overhead evidence, not an
end-to-end IBD, time-to-tip or consensus-validation speed claim. No node,
network peer, chain data or production datadir participates in the measurement.

## Reproduction and validation

```sh
bash tools/scripts/cold_start_snapshot_metadata_selftest.sh --cold-start --bench
bash tools/scripts/cold_start_snapshot_metadata_selftest.sh
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
bash tools/scripts/cold_start_timing_selftest.sh
bash tools/scripts/cold_start_seed_scan_selftest.sh
```

All pass. The optional final selftest argument selects a saved source script.
The baseline passes behavior checks and fails the one-command budget. The
candidate passes size boundaries, missing/refused metadata, epoch, filenames
with spaces, newest selection, ties in both orders, empty lists and explicit
override without any metadata calls. A `>=` to `>` mutation fails epoch-zero
selection. Applying only the implementation patch to clean HEAD also passes.
Related checks cover fifteen isolated tip polling cases, seed readiness, and
five startup timing/threshold cases.

Bash syntax, architecture-tree, shell-host-assumption, pipefail-status,
discarded-status, core-seal-root-mirror and `git diff --check` pass. No compiled
source changes; compiler and live-chain tests do not establish this shell-only
claim. ShellCheck is unavailable. `timeout 50 make -j2 lint-fast` exits 124
during initialization after reporting missing Tor archives and unchanged
generated templates. No aggregate lint or public-node build pass is claimed.

The owned incremental diff consists of the inline selector, its extension to
the existing selftest, the Make recipe, the shrinking lint baseline and this
note. All four existing files contained earlier work; do not stage their whole
diffs as this slice. Entry copies and the isolated selector patch reside under
`/tmp/worldstream-coldstart-metadata/`. The pre-existing index was verified
unchanged by comparing exported binary patches. The exact incremental diff
was reviewed; it includes no credentials, wallets, logs, caches, binaries,
production data or generated artifacts. Consensus source, normal independent
validation, optional acceleration policy and Hetzner-owned runtime, scheduling
and database code remain unchanged.

Publication is incomplete: fetch cannot write `.git/FETCH_HEAD` because Git
metadata is read-only; `origin/main` is absent locally; the origin branch
lookup cannot resolve GitHub. No commit, push or remote-SHA verification is
claimed. Publication requires completing aggregate validation, separating this
slice from existing work, and integrating current upstream in an environment
with writable Git metadata and working origin access.
