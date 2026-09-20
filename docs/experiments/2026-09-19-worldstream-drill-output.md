<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream recovery benchmark output recording

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. This slice changes only
`tools/scripts/netdisrupt_two_node_run_and_record.sh`, adds its hermetic
`netdisrupt_drill_output_selftest.sh`, and records this experiment. The runner
was clean at entry; unrelated staged and unstaged work is preserved.

The runner scanned its captured recovery-drill transcript three times with
three sed/tail pipelines to record elapsed seconds, artifact path and follower
RPC port. One awk pass now extracts all three, preserving the last matching
value, empty-field defaults, leading zeroes, ledger bytes and verdict exit
codes. The runner exposes the regression with `--selftest`, before creating
any ledger or running a drill.

This reduces post-drill instrumentation overhead. It does not shorten the
measured recovery interval or demonstrate faster end-to-end IBD. No node
runtime, database tuning, scheduling, consensus or validation code changes.
Optional acceleration and independent Zclassic validation are unchanged.

## Measured fixture

Host: Linux x86_64, AMD EPYC 7402P, 48 logical CPUs, Bash 5.2.21. Warm local
shell fixture, no network or node: 100 parses of the same 256 KiB transcript
per trial. Both versions use the production parser extracted from their source.

| Measurement | Before | After |
|---|---:|---:|
| Trial 1 wall seconds | 2.736 | 1.799 |
| Trial 2 wall seconds | 2.871 | 1.806 |
| Trial 3 wall seconds | 2.879 | 1.801 |
| Median wall seconds | 2.871 | 1.801 |
| External parsers per recording | 6 | 1 |

The median fixture cost fell about 37%. Timings are descriptive, not pass/fail
thresholds. The deterministic regression gates process count and output.
It covers missing fields, repeated fields, malformed values, a malformed
endpoint following a valid endpoint on the same line, whitespace, literal
shell metacharacters, empty ports and a long transcript. Six isolated whole
runner cases verify exact ledger bytes and pass/fail/skip/seam/stalled/error
exit behavior using a canned drill and temporary history directory.

Reproduce from this checkout:

```bash
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/netdisrupt_two_node_run_and_record.sh > /tmp/worldstream-drill-before.sh
bash tools/scripts/netdisrupt_drill_output_selftest.sh --bench /tmp/worldstream-drill-before.sh
bash tools/scripts/netdisrupt_drill_output_selftest.sh --bench
bash tools/scripts/netdisrupt_two_node_run_and_record.sh --selftest
```

The old source passes behavioral checks and deliberately fails the final
one-parser budget (six processes observed). The changed source passes.

## Validation and limits

- New parser and isolated runner regression: pass.
- Existing two-node drill and stopwatch evidence judge selftests: pass against
  the pre-existing working-tree versions, which contain unrelated edits.
- Bash syntax for both slice scripts: pass. ShellCheck is unavailable; this
  slice contains no compiled code.
- Direct pipefail-status, discarded-status, shell-host-assumption and
  architecture-tree gates: pass. The shell gates were repeated after staging
  the new selftest so their tracked-file scans include it.
- `git diff --check`: pass. Exact runner diff and new files reviewed; only
  source, tests and this report belong to the slice. No credentials, datadirs,
  generated files, logs or binaries are included.
- `make lint-fast` reached both its initial 45-second bound and a subsequent
  180-second bound during setup without a gate result. Full publication lint
  evidence remains unavailable; the direct applicable shell gates above pass.
- `make -j2 z23` encountered the absent Tor submodule and read-only Git config
  while preparing dependencies; the stalled build was interrupted. The public
  binary was unavailable, so the source navigator and real-node acceptance
  could not run. No full-build or real-chain performance claim is made.

The scoped Git tool can fetch the development branch and stage these files,
although shell operations against `.git` report read-only metadata and direct
remote lookup cannot resolve the origin host. Publication requires a separate
commit, branch-only push and freshly fetched remote SHA comparison; the
measurements above do not establish that publication succeeded.

The normal path-scoped commit attempt was refused because Git could not create
`.git/index.lock` on the read-only filesystem. The three slice files remain
staged; no commit or push was made. No hook or filesystem restriction was
bypassed. Publication remains pending writable Git metadata and the missing
broader validation evidence.
