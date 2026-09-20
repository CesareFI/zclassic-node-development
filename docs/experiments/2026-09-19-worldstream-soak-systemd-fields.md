<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream soak collector: parse service fields once

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. This slice owns only the soak evidence
collector, its focused regression, and this record. The large inherited
Worldstream worktree remains separate.

## Bottleneck and baseline

Every soak evidence sample fetched `systemctl show` once, then started a
separate `sed | head` pipeline for each of `NRestarts`,
`ActiveEnterTimestamp`, and `MainPID`. A hermetic complete `collect` sample
with mocked RPC, systemd and RSS inputs started 14 `sed`/`head` processes;
six existed only to reread those three already-fetched service fields.

The collector now walks the captured response once with Bash builtins. It
keeps the old first-valid unsigned-integer behavior for restart count and PID,
the first nonempty timestamp, and null-on-missing or malformed evidence. The
same complete sample starts eight text tools, a 43% reduction in this measured
process count. RPC and RSS parsing account for the remaining eight and are
outside this slice.

This is observer overhead and evidence-integrity work. The hourly production
cadence means it is not an end-to-end IBD speedup, and none is claimed.

## Reproduction and validation

```sh
bash tools/scripts/soak_evidence_collect_fields_selftest.sh
bash tools/scripts/soak_evidence.sh --selftest
bash -n tools/scripts/soak_evidence.sh \
  tools/scripts/soak_evidence_collect_fields_selftest.sh
```

The focused regression exercises valid fields after malformed duplicates,
timestamp conversion, missing/malformed fields, JSON null preservation, and a
deterministic text-tool budget. Against the pristine `HEAD` collector it
reports 14 calls; the changed collector reports eight. The registered soak
selftest runs the regression and all existing verdict and collection cases.

No C, consensus, cryptography, validation, wallet, peer scheduling, block
request scheduling, database, node runtime, or acceleration-policy source is
changed. No node, network, production datadir, credential, binary, cache, or
generated artifact participates.

Publication remains environment-blocked: `.git` is read-only, so fetch,
staging and committing cannot update Git metadata, and origin access is not
available. No commit, push, or remote-SHA equality claim is made.
