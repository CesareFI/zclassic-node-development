<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: keep startup benchmark trials fresh

Scope: startup measurement isolation in `tools/speedrun.c`, its fixtures,
and the `make speedrun-selftest` entry point. No node, consensus, validation,
peer scheduling, database or optional-acceleration behavior changes.

Baseline: checkout HEAD `c1f7863d098e1efaa8deba240c580ae0559312a5`, with
existing uncommitted startup-reporting changes preserved. The failing witness
uses that pre-edit working file, rather than claiming a clean HEAD benchmark.
Host: Linux x86_64, GCC 14.2.0. All trials use disposable fixture directories
and a stubbed boot boundary; no network, node or production datadir is used.

## Reproduction

The tool chose `/tmp/zcl23-speedrun-<pid>` and ignored `mkdir` failure. Its
output explicitly leaves state behind for inspection. After PID reuse, an
existing directory therefore becomes the next purported fresh trial's input.
That mixes resume cost into startup measurements and prevents reliable
identification of startup/IBD bottlenecks. A setup error could also proceed
into boot and produce a startup duration.

The regression invokes the actual entry point in two processes with the same
fixture PID. Directory operations use the real filesystem, redirected beneath
one temporary root. The boot stub requires an empty directory and leaves a
sentinel for the next trial. Before the fix, the first trial passes and the
second encounters the previous trial's sentinel. Afterward, both trials use
distinct empty directories with mode 0700. Injected `ENOSPC` causes exit 1
with zero boot calls and zero clock reads; no startup result is printed.

The change uses `mkdtemp` and checks its result before starting the clock.
It preserves each trial's artifacts, boot configuration and timing boundaries.
This establishes reproducible inputs, not faster sync: no elapsed IBD speedup
or time-to-tip measurement is claimed.

## Validation

```bash
bash tools/scripts/speedrun_datadir_selftest.sh --analyze
bash tools/scripts/speedrun_measurement_selftest.sh
```

The first script also accepts an absolute source path to replay the old
implementation. The existing reporting fixture now substitutes `mkdtemp`
instead of `mkdir`; successful and failed boot still report exactly 2345 ms
while withholding unobserved tip and validation completion claims.

C23 `-O2 -Wall -Wextra -Werror`, GCC static analysis, shell syntax,
architecture-tree, discarded-status and pipefail-status checks pass. Both
shell lint gates' own selftests pass. Whitespace checking passes.
The adjacent `bench_fresh_sync_datadir_selftest.sh` isolation regression passes.
Full `make lint` exceeded a bounded 45-second attempt during preparation;
`make speedrun-selftest` similarly exceeded 30 seconds before its recipes.
Both recipes pass when invoked directly as shown above; Make integration is
not claimed. The built navigator is unavailable in this checkout. The direct
fixture commands do not need a linked node.

Publication remains unavailable in this execution environment: `.git` is
read-only (fetch cannot write `FETCH_HEAD`) and GitHub DNS lookup fails.
Staging the new files also fails because `index.lock` cannot be created.
The branch remains `agent/worldstream-ibd-20260918`; no commit, push or remote
SHA verification is claimed. Existing unrelated staged and unstaged work is
preserved.
