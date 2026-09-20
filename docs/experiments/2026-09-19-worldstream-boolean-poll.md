<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: compact boolean evidence polling

Branch: `agent/worldstream-ibd-20260918`; HEAD at entry:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

`node_slo_probe.sh` reads explorer readiness through `evidence_json_bool`.
The shared reader started one external sed process for every compact boolean
observation. The candidate uses Bash for single-line responses of at most
4096 characters, preserving the last valid match on the first matching line,
exact output bytes, absent-value success, and the existing boolean-prefix
policy. Longer or multiline diagnostic bodies retain the existing sed path.
This is a telemetry field reader, not a general JSON decoder.

The baseline is the working library at entry, SHA-256
`260028761a4bf79c4bc51c1d4ef2f506002448b7b5edba75ad6f2beb101c352e`.
Earlier dirty reader changes are prerequisites, not work authored in this
slice. The slice changes that function, tightens the existing reader test's
process budget, adds a dedicated regression, and registers it in
`evidence-selftest`. Other staged and unstaged work is preserved.

## Measurement

Linux x86_64, kernel 6.8.0-139-generic, Bash 5.2.21, GNU sed 4.9, `LC_ALL=C`,
warm tools and filesystem caches; uncontrolled ambient host load. The fixture
is a 55-byte compact response with height, stage and readiness fields. Three
sequential repetitions per implementation, 2000 reads per repetition:

| Observation | Entry baseline | Candidate |
|---|---:|---:|
| Wall seconds | 5.280 / 5.234 / 5.027 | 0.141 / 0.142 / 0.141 |
| External tools per 100 reads | 100 | 0 |

The median observer cost fell about 97%. These are synthetic reader timings,
not IBD throughput or time-to-tip measurements. No node, peer, chain data,
production datadir or network participates.

## Validation and remaining limits

Reproduce the focused test and informational timing with:

```sh
bash tools/scripts/evidence_bool_poll_selftest.sh --bench
bash tools/scripts/evidence_json_readers_selftest.sh
```

The entry baseline passes value fixtures and fails the new process budget.
A mutation that removes the greedy prefix fails duplicate-field selection.
The regression covers exact newline output, missing fields, whitespace,
duplicate fields, invalid values, line boundaries, large input and the
4096-character fallback boundary. All eleven scripts in the current evidence
test recipe pass directly; the soak-evidence selftest also passes.

Bash syntax, architecture-tree, shell-host-assumptions, pipefail-status,
discarded-status and `git diff --check` pass. No compiled source changes;
compiler and live-chain tests are not applicable to this reader slice.
ShellCheck is unavailable. `make evidence-selftest` timed out after 45 seconds
and `make lint` after 60 seconds during initialization. Full lint is unverified;
the isolated evidence recipe is separately executable without that startup.

Consensus, validation semantics, optional acceleration policy and Hetzner-owned
code are unchanged. The exact slice contains no credentials, logs, binaries,
caches or generated artifacts. Temporary baseline snapshots, test output and
the isolated slice patch are under `/tmp/worldstream-evidence-bool.q1DSjR/`.

Publication remains incomplete: fetching cannot write `.git/FETCH_HEAD`, and
staging cannot create `.git/index.lock` on the read-only Git directory. The
remote lookup also fails to resolve GitHub. No commit, push or remote SHA
verification is claimed. The staged diff remains byte-identical to entry.
Do not stage the entire dirty library, Makefile or existing regression as this
slice; each already contained earlier work.
