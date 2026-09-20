<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Cold-start probe artifact quoting

Worldstream surface: external time-to-tip benchmark instrumentation only.
Base HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The checkout already contained extensive
uncommitted changes; the baseline below is the working probe at session entry,
not a clean HEAD build. Existing changes remain separate from this slice.

The probe sourced `stopwatch_json_lib.sh`, then replaced its `json_string`
with an older wrapper that used command substitution for escaping. Each
artifact emits eight quoted fields, so the override added eight shell
processes beyond the caller's existing substitutions. Removing that override
reuses the already optimized shared formatter. Numeric fields, acceptance,
timestamps, and artifact contents are unchanged.

## Measurement

Linux 6.8.0-139-generic x86_64, Bash 5.2.21, `LC_ALL=C`. Three trials of
100 complete artifact writes to an isolated temporary directory used a fixed
clock and identical short strings containing quotes, backslashes, tabs,
carriage returns and newlines. Ordinary filesystem caches were warm; ambient
host load was uncontrolled. No node, peer, or production datadir was used.
The shared library was held constant at SHA-256
`22d697042e699ee78b0009177864c88f2c68e8bb01bc8240413f2e420ebcbb0a`.

| Trial | Baseline wall seconds | Reused formatter wall seconds |
|---|---:|---:|
| 1 | 3.565 | 2.691 |
| 2 | 3.559 | 2.717 |
| 3 | 3.509 | 2.670 |

Median wall time fell about 24%. This is artifact-writing overhead, not
measured IBD or time-to-tip improvement. Timing is informational; the
regression asserts the process boundary directly without a timing threshold.

## Reproduction and boundary

Run `bash tools/scripts/cold_start_artifact_quote_selftest.sh --bench`.
An optional final argument selects a baseline probe. The test loads only
the real helper region, including the library import and any overrides;
it does not run the probe's startup or live operations. It compares complete
JSON and text artifacts for pass, skip, fail and seam verdicts against the
former formatter, then checks that escaping runs in the quoting caller's
process. The baseline preserves bytes but fails that process-budget check;
the modified probe passes both. The probe's existing `--selftest` now runs
this regression too.

The complete probe self-test, shared quote/string regressions, shell syntax,
architecture, shell-host-assumption, discarded-status, pipefail-status-pipe,
and `git diff --check` checks passed. Shared regressions include every non-NUL byte.
The aggregate `make lint-fast` did not finish its prerequisites and was
interrupted; no aggregate lint pass is claimed. Its output reported missing
Tor archives and unchanged generated templates. A serial retry with a
45-second bound also timed out in prerequisites. ShellCheck is unavailable.
This shell-only slice requires no C compiler change or generated interfaces.
No consensus, validation, acceleration defaults, peer scheduling, database,
or production-state code is changed. No secrets or generated output belong
to the slice.

Publication is unavailable in this session: `.git` is read-only, so fetching
fails when writing `FETCH_HEAD`; the read-only `git ls-remote origin` check
also fails because GitHub DNS is unavailable. No commit, push, or remote SHA
verification is claimed. The local change consists only of the probe's
formatter deletion/self-test call, the new regression, and this note.
