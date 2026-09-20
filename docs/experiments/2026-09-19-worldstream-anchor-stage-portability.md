<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Avoid repeated bootstrap snapshot staging with BSD stat

Worldstream scope: optional snapshot/bootstrap preparation. Baseline source:
`c1f7863d0` (`tools/seed_anchor_snapshot.sh`). No peer scheduling, database
tuning, node runtime, consensus, or validation code changes.

The staging script already skips a nonempty destination of the same size.
Its GNU-only size queries fail on BSD stat, substituting zero for both sizes
and defeating that skip. Repeated staging therefore copies the snapshot again.
The fix uses the existing GNU/BSD fallback pattern from `zcl-logrotate.sh`.
Unknown sizes still cause a copy; the final unknown-size display remains `?`.
The shell portability baseline shrinks from three GNU option sites to one.

## Reproduction and measured work

On Linux x86_64 with Bash 5.2.21, the hermetic selftest uses a 64 MiB zero-filled
source and an identical staged destination. A PATH shim emulates acceptance
of GNU or BSD size options and delegates successful reads to host stat.
Copy attempts are counted at the actual cp invocation; copies execute normally.
No live node, network, private material, or production datadir is used.

```bash
git show c1f7863d0:tools/seed_anchor_snapshot.sh > /tmp/anchor-stage-before.sh
bash tools/scripts/seed_anchor_snapshot_selftest.sh /tmp/anchor-stage-before.sh 64
bash tools/scripts/seed_anchor_snapshot_selftest.sh tools/seed_anchor_snapshot.sh 64
make seed-anchor-snapshot-selftest
```

| Same-size case | Baseline copy attempts | Fixed copy attempts |
| --- | ---: | ---: |
| GNU options | 0 | 0 |
| BSD options | 1 (regression fails) | 0 |

The fixed BSD case avoids submitting 67,108,864 bytes to a redundant copy.
This measures avoided work, not physical disk traffic or elapsed IBD time;
filesystem caching and copy optimizations affect physical traffic. Native
macOS execution and end-to-end time-to-tip remain unmeasured.

The regression also checks changed size, missing target, unavailable stat,
zero-length snapshots, missing source, and absent datadir. Copies are compared
byte-for-byte. The test target uses only isolated fixtures.

## Validation and boundaries

Passed: shell syntax, the focused regression, shell-host-assumption checks and
their readiness/peer-tip support tests, architecture checks, the consensus-core
seal (554 files and 80 sections), and `git diff --check`.

`make -j4 lint` exited 2 before completion: this clean clone lacks vendor
dependencies, and downloading zlib/OpenSSL failed with `Could not resolve
host: github.com`. Full lint is not claimed green. No C source changed.

Snapshot staging remains optional. Size equality only retains the existing
staging behavior: it is not evidence that a snapshot is valid. The node's
independent snapshot verification and all consensus rules are unchanged.
