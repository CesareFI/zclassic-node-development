<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: service-property observation during IBD

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5`, development branch
`agent/worldstream-ibd-20260918`. Linux x86_64, AMD EPYC 7402P,
Bash 5.2.21, ordinary warm filesystem caches and ambient host load.

## Measured bottleneck

`node_slo_probe.sh` already obtains service properties in one call, but
`evidence_systemd_field` starts `sed` and `head` for every property read.
The four properties used by each node's SLO sample therefore start eight
external text tools after the service response has arrived. The shared reader
also serves the intervention ledger's eight property reads.

The reader now uses Bash `read` and literal property matching. It preserves
the first matching line, empty values, whitespace, backslashes, exact integer
text and the successful empty result when a property is absent. Native
systemd property names are literal identifiers, not regular expressions.

| Fixture measurement | Before | After |
|---|---:|---:|
| External text tools per four-property sample | 8 | 0 |
| Wall time, 250 samples / 1,000 reads | 4.058 s | 1.264 s |
| User CPU | 0.813 s | 0.256 s |
| System CPU | 6.121 s | 1.113 s |

The baseline is the exact pre-edit helper. Other uncommitted changes in the
checkout were held constant. The benchmark uses a fixed four-property service
response and the command substitutions used by the SLO consumer. It performs
no systemd, RPC, network or datadir operation. Timing is informational; the
zero-tool budget is deterministic. These are observation costs, not measured
IBD or time-to-tip gains.

## Reproduction and validation

```sh
bash tools/scripts/evidence_systemd_field_selftest.sh --bench
make evidence-selftest
```

The script accepts an optional final library path for baseline comparison.
The baseline passes byte checks and fails the zero-tool budget. The regression
checks missing/empty fields, terminated/unterminated input, exact key matching,
duplicate fields, literal values and wide numbers, plus differential non-NUL
byte coverage. A mutation removing the first-match return is rejected.

The evidence and tip-agreement Make targets passed. Direct hermetic SLO
probe, hold-judge and pager suites passed. A separate archive of the base
commit with only this reader change and its test also passed the new test and
the intervention, declaration, external-availability and SLO probe suites.
Shell syntax, architecture, shell-host-assumption and whitespace checks passed.

Full node build and lint evidence remain unavailable: Git metadata is mounted
read-only, preventing Tor submodule initialization, and dependency downloads
fail GitHub DNS resolution. The bounded full-lint attempt expired during its
prerequisite build. The registered SLO aggregate also requires a native test
build; that attempt was interrupted after dependency failures. Direct shell
fixture results do not replace that evidence.

## Scope

Only the shared service-property reader, its shell regression, Make test
wiring and this record belong to this slice. Existing dirty work is preserved.
No consensus, cryptographic validation, optional acceleration, peer scheduling,
database behavior or production state changes. No logs, binaries, credentials
or benchmark output belong in the commit.

Publication was attempted but staging failed because `.git/index.lock` cannot
be created on the read-only filesystem. The final fetch also could not write
`FETCH_HEAD`, and the remote SHA query failed DNS resolution. No commit or
push was made; the existing staged work remains byte-identical.
