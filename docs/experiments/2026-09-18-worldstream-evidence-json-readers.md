<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream shared JSON observer readers

The shared integer, string and boolean readers used by the external sync
observers started `sed` and `head` for every field. With `pipefail`, a large
multiline response containing repeated fields returned the selected value
but a failed status when `head` closed its input early. The fixture reproduced
exit 4 in all three readers on this host. Each reader now uses one `sed`,
stopping after the first matching line, with a Bash here-string as input.
There is no producer pipeline to break when the reader stops.

The selection rules remain the same: last match within the first matching
line, absent fields empty, wide integers kept as text, and the existing
compact-field prefix/escape behavior. These are not general JSON parsers.
Values are tested as callers consume them, through command substitution;
the here-string supplies a final newline to an unterminated input.

Owned surface: only `evidence_json_int`, `evidence_json_str`, and
`evidence_json_bool` in `tools/scripts/lib/evidence_sources.sh`, their new
`tools/scripts/evidence_json_readers_selftest.sh`, one invocation in
`make evidence-selftest`, and this note. Other pending Worldstream edits
are outside this slice. No node, consensus, cryptography, validation,
acceleration, peer scheduling or database behavior changes.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including pre-existing local edits.
Baseline library SHA-256:
`089b26bec028bd8fafa62a27a1c097d137f51a0f79d8ca5760bb8a21743113f9`.
Updated library SHA-256:
`91664e41b830f37c414cb3315c3a45703801211fc4609f1bce99d5c51d65e42e`.
The three original reader bodies also match HEAD, and the new readers were
separately tested in an archive of HEAD without other pending changes.

Measured on Linux x86_64, AMD EPYC 7402P, Bash 5.2.21 and GNU sed 4.9.
The benchmark repeatedly reads three fields from the same in-memory compact
response, using warm executable caches and ambient host load. No node,
network, datadir, or validation participates.

| Measurement | Before | After |
|---|---:|---:|
| External tools per three-field sample | 6 | 3 |
| Wall time, 500 samples | 4.979 s | 4.435 s |
| User + system CPU, 500 samples | 9.547 s | 4.666 s |

These are observer costs, not measured end-to-end IBD or time-to-tip gains.
Elapsed time is informational; value/status and process count are the gates.
Reproduce with `bash tools/scripts/evidence_json_readers_selftest.sh --bench`;
an optional final argument selects a saved baseline library. The baseline
fails the three large-response status cases and the process budget. A mutant
that stops on an unmatched first line fails the first/late-match cases.

The focused regression, tip-agreement recorder/judge, SLO probe, hold judge
and pager pass in both the working tree and isolated HEAD-plus-slice tree.
The intervention ledger, intervention front door and public explorer smoke
fixtures also pass. Shell syntax, host assumptions, discarded-status,
pipefail-status-pipe, no-API-keys, no-Python, architecture, whitespace and
core-root-mirror checks pass. The byte seal verifies 554 files and 80 sections.
This shell-only slice needs no node compiler change. Full `make lint` did
not finish within a 45-second bound; the aggregate Make invocations also
did not reach their test output before interruption. Direct fixture results
do not establish complete publication-gate evidence.

The branch fetch failed because `.git/FETCH_HEAD` is read-only; a separate
origin query failed to resolve GitHub. Preparing an isolated index for this
slice failed because Git could not write the modified library object to its
read-only object storage. No commit or push was made; publication and current
remote-SHA equality have not been established. No logs, binaries, temporary
benchmark output, generated files or secrets belong to the slice.
