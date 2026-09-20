<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream soak collector: decode sample fields in-process

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. This slice owns the soak evidence field
decoders, their focused regression, and this record. The inherited Worldstream
worktree remains separate.

## Bottleneck and baseline

At `HEAD`, every complete evidence sample started 15 `sed`, `head`, or `grep`
parser processes to decode three fields from an already-fetched systemd
response, two block-height responses, one security scalar, and the fixture RSS
line. Six processes reread the systemd response; the other nine decoded the
RPC/RSS scalars.

The collector now walks the systemd response once with Bash builtins and
decodes the already-captured scalar responses with Bash regular expressions.
The focused sample starts zero text-tool parser processes, a 100% reduction
for this measured work. It preserves the former first-valid-line behavior and
the greedy last-valid scalar behavior within a line, including a valid value
followed by a malformed duplicate. Missing or malformed evidence remains JSON
`null`.

This removes measurement-process churn and makes sync/soak instrumentation
less intrusive. The production soak cadence is hourly, so no end-to-end IBD
speedup is claimed.

## Reproduction and validation

```sh
bash tools/scripts/soak_evidence_collect_fields_selftest.sh
bash tools/scripts/soak_evidence.sh --selftest
bash -n tools/scripts/soak_evidence.sh \
  tools/scripts/soak_evidence_collect_fields_selftest.sh
```

The complete evidence selftest family, architecture-tree gate,
pipefail-status gate, and shell-host-assumptions gate also pass. ShellCheck is
unavailable on this host. The aggregate Make front door was interrupted after
a bounded period of silent initialization; the affected scripts and gates
above were then run directly. No compiled source changed, so compiler and chain
validation tests are not applicable to this instrumentation-only slice.

No C, consensus, cryptography, validation, wallet, peer scheduling, block
request scheduling, database, node runtime, or acceleration-policy source is
changed. No node, network, production datadir, credential, binary, cache, or
generated artifact participates.
