<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: missing-counter profile observer cost

Scope: `jnums1` in `tools/scripts/fold_profile.sh`, its isolated regression,
and registration in `make fold-profile-selftest`. This is profiler overhead,
not measured chain synchronization throughput or time to tip. No node, peer,
production datadir, consensus predicate, or validation setting was changed.
Optional acceleration and normal independent validation are unaffected.

The checkout was on `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with substantial pre-existing changes.
The starting profiler bytes had SHA256
`33c5ee6a1d588ff6b8e9f05b89d1b0a7712e523e45891d5e19bb86598a641411`;
this baseline is the working file, not the HEAD version. After this slice:
`036b0a90f8b62f2de928460101d85a4b0c9ad8f423f5601f86a004b9ab6bcff7`.
Unrelated changes must not be included when committing this slice.

An incomplete profile made each missing counter run a regular expression
over the entire diagnostic line. The change checks for the literal telemetry
key before applying the existing regex. The regex still decides field
boundaries and values; missing-value zeros, first-integer selection, duplicate
policy, exact wide integer text, and input draining remain unchanged.

Measured on Linux x86_64, AMD EPYC 7402P, GNU awk 5.2.1, warm synthetic files,
no RPC/network load. Each case reads the profile 30 times through the actual
uninstrumented shell function, including process creation and output checks.
The sparse case has 50,000 diagnostic fields and one of 12 requested counters
at the end (1,227,801 bytes). The complete case has all 12 counters before
the same diagnostic tail.

| Case | Before | After |
|---|---:|---:|
| Sparse wall time | 11.53 s | 2.16 s |
| Sparse regex calls per read | 12 | 1 |
| Complete wall time | 0.60 s | 0.60 s |

These single-run timings are supporting observations, not latency acceptance
thresholds. The regression gates deterministic work instead: one regex call
for the sparse case. It fails on the baseline with 12 calls. A complete
profile and malformed/nested lookalikes also assert exact output.

Reproduce without a node:

```sh
sh tools/scripts/fold_profile_missing_keys_selftest.sh --bench
# A saved pre-change working file can be measured without accepting its budget:
sh tools/scripts/fold_profile_missing_keys_selftest.sh --baseline --bench /path/to/before.sh
make fold-profile-selftest fold-profile-summary-selftest
```

Validation: new regression passed with GNU awk, mawk, and BusyBox awk;
existing CSV, scan, parser-process budget, 35 RPC refusal/recovery cases,
wide-duration summary, and long-history checks passed. Shell syntax checks,
the shell-host-assumption gate and its selftest, the architecture gate, and
`git diff --check` passed. No compiled source changed; ShellCheck is unavailable.

Full `make lint` did not finish within the bounded 60-second attempt and is
not claimed green. The public binary is unavailable; its build encountered
read-only Git metadata during Tor preparation and was interrupted after no
further progress. Fetch cannot write `.git/FETCH_HEAD`; remote inspection
cannot resolve GitHub. Commit, push, upstream integration, and exact remote
SHA verification remain unperformed under these environment restrictions.
The branch has not been changed. Raw fixtures and measurements stay in `/tmp`.
