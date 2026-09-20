<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stop stage-window growth at a complete timing triple

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fold-profile observer expanded each stage window until a closing brace,
even when `us`, `calls` and `adv` were already complete. Additional fields
inside that object therefore caused unnecessary copying during IBD sampling.
The reader now also stops expanding when it has a complete triple. Duplicate
searches still continue across the line; malformed prefixes and wide integers
still grow as needed. Closing-brace boundaries remain enforced.

This slice changes only that stopping condition and its explanatory comment,
adds `fold_profile_stage_tail_selftest.sh`, and invokes the regression from
the existing `fold-profile-selftest` target. Earlier changes in the sampler
and Makefile are prerequisites, not authored by this slice. The working-tree
baseline sampler SHA-256 is
`25cdeed41ce08badc970e5198d5f4e996b66c5ef78c44b90191ed6427880fb67`;
the candidate is
`5d8ace44df7a8da745865f5d2a46e322f4ad21e28eb68904c019f638f17aec71`.
Baseline snapshots and an isolated patch are under
`/tmp/worldstream-stage-triple/`. Do not commit the entire dirty sampler or
Makefile as this slice.

## Measurement

Linux x86_64, AMD EPYC 7402P, 48 logical CPUs, GNU awk 5.2.1. Synthetic
responses contain one stage timing triple followed by 0, 500 or 50,000 extra
fields inside its object. Three sequential baseline/candidate repetitions
use warm tools and ordinary filesystem caches, with uncontrolled ambient
load and a concurrent bounded lint initialization attempt. Each timing is
100 uninstrumented shell reader calls; instrumentation separately counts
the bytes returned by window copies.

| Extra stage fields | Baseline copied bytes | Candidate copied bytes | Baseline wall seconds | Candidate wall seconds |
|---|---:|---:|---|---|
| 0 | 43 | 43 | 0.46 / 0.46 / 0.46 | 0.44 / 0.44 / 0.45 |
| 500 | 26,583 | 128 | 0.47 / 0.48 / 0.47 | 0.49 / 0.49 / 0.48 |
| 50,000 | 3,324,855 | 128 | 2.88 / 2.89 / 2.94 | 2.18 / 2.19 / 2.18 |

The large fixture's median wall cost falls about 25%; smaller fixtures show
no material speedup. The large fixture uses one window copy instead of 15.
Input transport and later duplicate searches still consume the response.
These are observer-cost measurements, not real node IBD or time-to-tip
results. No production node, datadir or peer participated.

## Validation and publication limits

```sh
sh tools/scripts/fold_profile_stage_tail_selftest.sh --bench
make fold-profile-selftest
```

The baseline passes value checks but fails the new 128-byte work budget;
the candidate passes under GNU awk, mawk and BusyBox awk. Fixtures cover
later nested duplicates, malformed prefixes, absent keys, first matching
line, fractional-number refusal and exact integers through 1,000 digits.

Direct shell runs of the existing sampler, RPC refusal, drive, sparse-drive,
drive-window, stage-object, stage-window, scan, prefix, counter-prefix,
missing-key, summary, counts and history regressions pass. These include
35 failed/empty RPC refusals and recovery, exact 50-column CSV output, and
summary checks under three awk implementations. The canonical
`make fold-profile-selftest` target also passes, including the new regression,
bounded RPC client tests and bootstrap/epoch prerequisites. POSIX/Bash syntax,
architecture-tree, shell-host-assumption, pipefail-status and discarded-status
gates pass. `git diff --check` passes. ShellCheck is unavailable; no C source
changed, so compiler and live-chain tests are not claimed.

`make lint-fast` times out during initialization after 90 seconds and again
on a 60-second retry after the focused target passed; no aggregate lint pass
is claimed. Git fetch cannot write `.git/FETCH_HEAD` on the read-only
filesystem, and exact remote-branch lookup fails because GitHub cannot be
resolved. No commit, push or remote-SHA verification is claimed. Aggregate
lint and publication remain incomplete.

Consensus, cryptographic validation, optional acceleration policy and
Hetzner-owned scheduling, database and runtime code are unchanged. The
reviewed slice contains no secrets, logs, binaries, caches or build output.
