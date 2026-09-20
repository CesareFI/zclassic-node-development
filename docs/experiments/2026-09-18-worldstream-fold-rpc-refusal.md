<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stop fold sampling after an unusable RPC

Scope: copy-only IBD performance instrumentation in
`tools/scripts/fold_profile.sh`. No node, consensus, validation, peer scheduling,
database, or acceleration behavior changes.

The starting checkout was `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`, with pre-existing staged and unstaged work,
including the profiler's batched parsers and its CSV selftest. Those changes
are preserved; these measurements compare the working profiler immediately
before and after this slice, not an otherwise clean HEAD.

## Failing witness and measured cost

The sampler checked only whether the first RPC printed anything. A nonzero
exit with partial output was accepted; subsequent failed or empty replies
could become zero-valued fields in the final CSV row. The summary differences
the first and last rows, so that false observation can corrupt the reported
stage costs. Polling also continued after the required observation was lost.

The hermetic regression extracts the actual sampling functions and substitutes
only RPC responses and the clock. It uses no node, network, or datadir.

| First RPC returns nonempty JSON and exits 7 | Before | After |
|---|---:|---:|
| RPC invocations per attempted sample | 5 | 1 |
| Invalid rows appended | 1 | 0 |

This removes four unnecessary requests (80%) for that failure case. It is an
observer-cost measurement, not a claim of faster end-to-end chain download.
The exact before-change witness was:

```text
fold-profile RPC selftest: FAIL: drive/failed_output appended an unusable sample (5 RPCs)
```

Each required response now must exit successfully and be nonempty before the
next request starts. A refusal names the endpoint and preserves the previous
CSV bytes. Successful nonempty replies retain the existing missing-field
sentinels and parser semantics; an empty response is no longer treated as an
object with missing fields. This is not general JSON/schema validation.

## Reproduction and validation

```sh
sh tools/scripts/fold_profile_rpc_selftest.sh
sh tools/scripts/fold_profile_selftest.sh --bench
make fold-profile-selftest
```

The RPC test accepts an optional profiler path to exercise a saved baseline.
It covers all five endpoints with failed nonempty, failed empty, and successful
empty responses: 15 refusals, exact request counts, unchanged CSV bytes, no
observation formatting after failure, diagnostic presence, and later recovery.
It passes under both `/bin/sh` and Bash. The existing CSV regression passes,
including exact wide integers, duplicate-key policies, column ordering and
missing-field sentinels. Healthy samples still use six external parser tools.
The Make target runs both regressions.

Shell syntax checks, the discarded-status and pipefail-status repository
gates, and `git diff --check` passed. Publication remains subject to the full
build/lint gates and remote verification; these fixture results establish no
live-node acceptance or time-to-tip speedup.

Session limitations: `make fold-profile-selftest` hit a 60-second setup timeout;
both recipe scripts passed directly. `make z23` reached Tor initialization,
which failed to write the read-only `.git/config`; the unfinished build and
`make lint` were interrupted without claiming acceptance. No compiler or node
code changed. ShellCheck was unavailable. Git fetch also refused the read-only
`.git/FETCH_HEAD`, `origin/main` was absent, and a fresh remote query failed
GitHub DNS resolution. No commit, push, or fresh remote-SHA verification was
possible; the existing staged work was left untouched.
