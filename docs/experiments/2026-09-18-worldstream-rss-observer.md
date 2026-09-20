<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream RSS observation cost

Base commit: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. The checkout already contained other
uncommitted Worldstream slices. This slice changes only `evidence_rss_kb`,
adds `tools/scripts/evidence_rss_selftest.sh`, and registers that test in
`make evidence-selftest`. Other existing changes are preserved.

The shared reader samples process RSS for `node_slo_probe.sh` during sync
and for `soak_evidence.sh`. Each sample previously started `grep`, `sed`
and `head` to read one kernel status field. Missing VmRSS also returned
nonzero under pipefail, contrary to the reader's empty-observation contract.

Bash now reads the status record directly, retaining decimal text without
arithmetic conversion. Missing fields and failed reads produce an empty
successful observation. They do not fabricate a zero. No production path
override or cached process state is introduced.

## Measurement

Linux x86_64, Bash 5.2.21, ordinary warm filesystem caches and ambient host
load. Each run captures 500 readings of the same six-line status fixture,
including the callers' command substitution. No node runs in this benchmark.

| Measure | Before | After |
|---|---:|---:|
| External text tools per reading | 3 | 0 |
| Wall seconds, 500 readings | 2.115 | 0.651 |
| User seconds | 0.464 | 0.152 |
| System seconds | 3.771 | 0.551 |

Wall time is informational; the regression asserts the process budget and
output bytes. These figures describe observation overhead, not IBD or
time-to-tip gains. Bash still forks for the caller's command substitution.

Reproduce with `bash tools/scripts/evidence_rss_selftest.sh --bench`.
An optional final argument selects an older library. The test redirects only
the function's `/proc/` path to local fixtures. The baseline fails on missing
observations and the process budget; a wrong-field mutation fails byte checks.
Cases include zero, wide integer text, whitespace, caller IFS, invalid units,
missing fields, invalid/absent PIDs, and a failed file read.

## Validation and limits

The RSS regression and the evidence string, peer-count, service-property,
intervention, public-explorer, soak, SLO probe/hold/pager, and tip-agreement
fixture suites pass when invoked directly. Shell syntax, discarded-status,
pipefail, shell-host-assumption, architecture, and whitespace checks pass.
The consensus seal verifies all 554 files and 80 sections. No C source,
consensus rule, validation path, optional acceleration, peer scheduling,
database behavior, or production state changes in this slice.

Make-driven suites and `make lint-fast` did not reach their recipes during
the initial attempts and were interrupted after no further output beyond
unchanged template generation. The directly invoked fixture suites above
passed; a 30-second bounded Make retry also timed out during makefile
processing. The full Make/lint gates are not claimed complete. ShellCheck is
unavailable. No generated output or benchmark artifact belongs in the slice.

Publication remains blocked: Git metadata is read-only and origin lookup
fails because GitHub DNS is unavailable. No commit, push, upstream integration,
or remote-SHA verification is claimed.
