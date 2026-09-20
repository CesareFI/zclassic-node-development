<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: fresh-boot progress field observation

The fresh-boot proof started thirteen external parsers per sample to read
the header-admit cursor, H*, network tip and active blocker count. Replace
the two field-reader pipelines with Bash matching. Callers, sampling cadence,
missing-value sentinels, verdict math and acceptance thresholds are unchanged.
Scalar reads retain the first integer match on the first matching line;
stage reads retain newline removal and the existing within-object greedy
cursor selection. Integer text, negative sentinels and integer-prefix behavior
are preserved. These helpers remain field readers, not JSON validators.

This slice changes external instrumentation only. Consensus predicates,
validation, optional acceleration, peer/block scheduling, stalled-request
recovery, database behavior and production state are untouched.

## Baseline and measurement

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The baseline is the working
`fresh-boot-proof.sh` on entry, including pre-existing Worldstream edits;
it is not clean HEAD. Its SHA-256 is
`0eeeea98cce7feb9b298b94271e28eb765e0f48267706021bb186ccd0dc19ca8`.
The resulting script's SHA-256 is
`543fb32c91e6716a1271e21a816308fc1058c20a5bbe13a7eab6fe6819ed7c1b`.

Linux x86_64, AMD EPYC 7402P, Bash 5.2.21. Each run executes 500 samples
of four fields from two synthetic responses totaling 148 bytes per sample.
The fixture uses warm ordinary filesystem caches with ambient host load;
timing includes assertions and command substitutions. No node, RPC, peers,
chain corpus or datadir participates.

| Measurement | Before | After |
| --- | ---: | ---: |
| External parser processes per sample | 13 | 0 |
| Wall seconds, three runs | 8.917 / 8.731 / 8.970 | 2.784 / 2.858 / 2.856 |
| Median wall seconds | 8.917 | 2.856 |
| User + system CPU seconds, three runs | 19.416 / 19.031 / 19.391 | 2.993 / 3.065 / 3.063 |

The approximately 68% median reduction measures reader overhead, not
end-to-end IBD or time-to-tip improvement. Shell command substitutions remain.
The deterministic regression gate asserts zero external parsers; elapsed time
does not decide test success.

## Reproduction and validation

```bash
bash tools/scripts/fresh_boot_fields_selftest.sh --bench
bash tools/scripts/fresh_boot_frontier_selftest.sh
bash tools/scripts/fresh_boot_log_max_selftest.sh
bash tools/scripts/stopwatch_json_selftest.sh
bash tools/scripts/stopwatch_artifact_symmetry_check.sh --selftest
bash tools/scripts/stopwatch_evidence_judge.sh --selftest
```

The new selftest optionally accepts a final baseline-script path. Both readers
pass all 33 value/status checks; the baseline fails the process budget with
thirteen calls. Coverage includes whitespace, duplicate keys, multiple lines,
object boundaries, missing/null/quoted fields, zero, negative sentinels,
leading zeros, wide integers and existing integer-prefix handling. Removing
negative-number support from a scratch mutant fails the negative-height case.
Only reader functions are extracted; no test launches the boot harness.

All six commands above pass. Bash syntax, shell-host assumptions, pipefail
status pipes, discarded status, architecture, no-API-keys, no-Python, and
staged/unstaged `git diff --check` pass. The core seal verifies all 554 files
and 80 sections unchanged. No compiled source changed; compiler analysis is
not applicable to this shell slice.

`make -j4 z23` hit a 45-second bound after missing Tor archives triggered
submodule setup, which failed to write read-only `.git/config`.
`make lint` also hit a 45-second bound during prerequisites, without a final
verdict. Full build and publication acceptance remain unverified. Generated
template messages reported unchanged outputs.

Owned delta: the two readers and their reproduction comment in
`tools/scripts/fresh-boot-proof.sh`, the new
`tools/scripts/fresh_boot_fields_selftest.sh`, and this report. Preserve the
other existing edits in the harness and checkout; do not stage the entire
dirty harness for this slice. No secrets, datadirs, logs, binaries, caches,
generated files or temporary benchmark output belong to this delta.

Publication is incomplete. Fetch cannot write `.git/FETCH_HEAD`, and querying
origin fails GitHub DNS resolution. HEAD and the local cached development
remote-tracking ref both name the baseline SHA, which is not fresh remote
verification. No commit or push was made. The development branch is unchanged.

The next measurable observer cost remains repeated full-log scans for header
and chain maxima. A combined grep scan and a direct awk scan were tested
here and were slower; those experiments were discarded, and the existing
log reader and its selftest were restored byte-for-byte before this slice.
