<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream refold frontier reader

The refold-rate proof started three external parser processes per authoritative
H* read, or six when falling back to `cached_provable_tip`. Bash matching now
performs those reads without external parsers. The RPC calls, retry forms,
sampling cadence, rate thresholds and verdict math are unchanged. No node
runtime, consensus, validation, optional-acceleration policy, peer scheduling
or database behavior changes belong to this slice.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The changed harness was clean at
the start; other pre-existing staged and unstaged work was preserved. Baseline
harness SHA-256:
`879be1bca9073c378fd67220fddadf551c38919e014a672aa1d19a11ac4166c5`.
Updated harness SHA-256:
`1afc0bbd05e7c9d6b355a8f0a67b22049120ccc5a55b152086fa95e0028b9afd`.

Measured on Linux x86_64 with Bash 5.2.21, warm filesystem caches and
uncontrolled ambient host load. The fixture runs 100 rounds of three synthetic
responses: authoritative frontier, cached fallback and unavailable frontier.
No node, datadir, peer, network or sleep participates.

| Measurement | Before | After |
|---|---:|---:|
| External parser processes per three-read round | 15 | 0 |
| Wall time, 300 reads | 2.034 s | 0.027 s |
| User + system CPU, 300 reads | 4.481 s | 0.027 s |

These are parser costs, not end-to-end IBD or time-to-tip measurements.
Wall time is informational; the zero-parser-process check is deterministic.
Reproduce with:

```sh
bash tools/scripts/step1_refold_parser_selftest.sh --bench
```

An optional final script path selects a saved baseline. The baseline passes
all 22 field/fallback checks and fails the process-count gate. The fixture
checks first-integer selection, duplicate keys, exact field names, missing
and negative sentinels, zero, wide integer text, leading zeros, whitespace,
multiline boundaries, and both RPC argument forms. A mutation changing the
fallback sentinel from -1 to -2 is rejected. This remains a reader of known
frontier fields, not a general JSON parser.

The existing `step1_refold_rate_proof.sh --selftest` now runs the parser
regression before its seven unchanged rate-verdict checks. Both pass, along
with the cold-start stopwatch, artifact-symmetry and stopwatch-judge selftests.
Bash syntax, shell-host assumptions, pipefail-status-pipe, discarded-status,
no-API-keys, no-Python, no-warning-suppression and whitespace checks pass.
The core seal confirms all 554 files and 80 sections unchanged. This slice
contains only the harness, its fixture and this note; no secrets, datadirs,
binaries, logs, generated files or benchmark output are included.

Full `make lint` reached its 45-second bound during prerequisite compilation
after the zlib download failed on GitHub DNS. Publication is blocked:
fetch cannot write the read-only `.git/FETCH_HEAD`, `origin/main` is absent
locally, and the exact development-branch remote query also fails on DNS.
No completed publication gate, commit, push or verified remote SHA is claimed.
