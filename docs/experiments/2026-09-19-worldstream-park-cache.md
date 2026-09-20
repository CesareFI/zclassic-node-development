<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: quiet startup-log observation

The cold-start stopwatch's `log_named_park` scanned the complete node log on
every observation, including a quiet or parked startup. A synthetic 16 MiB
log without a marker was scanned 100 times for 100 polls. This is benchmark
observer overhead, not evidence of a chain-validation or peer-scheduling defect.

Measured on Linux x86_64, AMD EPYC 7402P, Bash 5.2.21. The fixture is freshly
written and read from the warm filesystem cache, with no node, network peer,
production datadir or cache flush. HEAD was
`c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`; the checkout already contained extensive
uncommitted Worldstream work. The source hashes below identify the tested
stopwatch bytes rather than implying HEAD contains that work.

| 100 polls of a 16,777,216-byte quiet log | Full scans | Wall seconds |
| --- | ---: | ---: |
| Existing working-tree source | 100 | 1.159 |
| Cache, reusing shared metadata helper | 1 | 0.372, 0.354, 0.367 |

Before stopwatch SHA-256:
`b3499e8f64e38275a4f465939725943859628f27cb85c08ad614cda08d7a21fe`.
After stopwatch SHA-256:
`ebc6c3bd76ac1f97ee227ab0ba35276a9c7df7a2d7bf620f7fc451ac5ac53261`.

The cache binds the path, inode, extent and precise modification/change
timestamps observed before scanning. It reuses both hits and confirmed misses.
Appends, truncation, replacement and same-size rewrites invalidate it. Read
errors are never cached. Symlinks, unavailable metadata and the seconds-only
BSD fallback retain the full scan. Latest-marker extraction and exit statuses
remain unchanged. The existing probe metadata helper moved into the already
shared stopwatch library; its lint baseline entry moved with it, with no
increase in allowed sites. The assisted probe keeps the same helper behavior.

Reproduce without starting a node:

```sh
bash tools/scripts/stopwatch_park_cache_selftest.sh
bash tools/scripts/stopwatch_park_cache_selftest.sh --bench
# An optional final argument selects saved pre-change stopwatch source.
bash tools/scripts/stopwatch_park_log_selftest.sh
bash tools/scripts/cold_start_to_tip_stopwatch.sh --selftest
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
```

The new regression fails against the saved baseline at unchanged-miss reuse.
Regression coverage includes hit/miss reuse, append during scanning, rewrite
with restored mtime, inode replacement, truncation, deletion/recreation,
symlinks, metadata failure, scan failure and datadir changes. The existing ten
marker compatibility cases, both full harness selftests, seed-log tests,
snapshot-metadata tests and Bash syntax checks passed. The shell host-assumption
gate passed with its existing total of 217 sites; the pipefail/status-pipeline
gate also passed. `git diff --check` passed.

No consensus, validation, runtime scheduler, database, wallet or acceleration
configuration changed. This experiment does not measure end-to-end time to tip.
Raw outputs and the pre-change source are under `/tmp/worldstream-park-slice`,
outside the proposed source changes.

Publication is blocked in this environment: `.git` is read-only, so fetching
cannot write `FETCH_HEAD`; GitHub DNS resolution also fails. No commit or push
is claimed. The cached origin branch SHA equals local HEAD, but that is not a
fresh remote verification. `make lint-fast` did not reach its gate results in
the initial run (interrupted); a 60-second bounded retry exited 124, also before
gate results. Full lint remains unverified. The two direct applicable checks
above passed; ShellCheck is unavailable. Only shell/source tests changed, so
no C compiler acceptance is claimed.
