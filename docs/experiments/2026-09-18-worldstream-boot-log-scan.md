<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream stopwatch boot-log observation cost

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`, Linux x86_64,
Bash 5.2.21. The checkout already contained unrelated uncommitted work.
The boot observer functions measured here were unchanged from that commit.
No node, peer, wallet or production datadir participated in this experiment.

The cold-start stopwatch reread its entire growing `node.log` twice on each
sample: `awk` counted prologue markers, then `sed | tail` recovered the last
self-respawn breadcrumb. One awk pass now returns both observations. Marker
syntax, breadcrumb matching and classification, monotonically retained boot
count, sample cadence, verdicts and validation are unchanged.

| Twenty observations of a 16 MiB fixture | Before | After |
|---|---:|---:|
| Log scans per observation | 2 | 1 |
| External tools per observation | 3 | 1 |
| Wall time | 3.111 s | 1.721 s |
| User CPU | 2.628 s | 1.432 s |
| System CPU | 0.559 s | 0.211 s |

The fixture uses ordinary newline-delimited text with markers at its end and
warm filesystem caches. Timing includes call-count instrumentation and ambient
host load; it is informational. The regression asserts scan/tool counts, not
a noisy elapsed-time threshold. These are observer costs, not measured IBD or
time-to-tip improvements. Each observation still performs a full log scan;
incremental reading remains a possible separately measured improvement.

Reproduce with:

```bash
bash tools/scripts/stopwatch_boot_scan_selftest.sh --bench
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/cold_start_to_tip_stopwatch.sh > /tmp/boot-scan-baseline.sh
bash tools/scripts/stopwatch_boot_scan_selftest.sh --bench /tmp/boot-scan-baseline.sh
```

The baseline passes behavior checks and intentionally fails the single-scan
budget. The test extracts the actual observer functions without executing
harness setup. It covers missing/empty logs, exact versus prose/subphase
markers, appends, truncation, accepted respawn suffixes, multiple breadcrumbs
on one line, trailing whitespace and an unterminated last line. Removing boot
count advancement fails the regression. The main stopwatch selftest runs this
test too. Four flag-catalog source-line references track the moved code.

Focused observer, complete cold-start stopwatch and artifact-symmetry selftests
pass. Shell syntax, architecture, shell-host-assumption, pipefail-status and
discarded-status checks pass. `git diff --check` passes. The public binary
build and full lint cannot complete because required vendored dependencies
cannot be downloaded: GitHub DNS resolution fails. ShellCheck is unavailable.
The flag-registry check remains red on nine pre-existing source-line pointers
in other modified files; it reports no stale pointer in the changed stopwatch.

Consensus, cryptographic validation, optional acceleration, peer scheduling,
database tuning and runtime reliability code are untouched. Existing dirty
work is preserved. Publication remains blocked by read-only `.git` metadata
and unavailable GitHub DNS; this is local evidence, not a published commit.
