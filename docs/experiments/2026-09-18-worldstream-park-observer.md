<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream named boot-stall observation cost

The cold-start time-to-tip stopwatch reads the most recent named boot stall
on every sample and at final readback. Its observer launched grep, tail and
sed inside a command substitution. Retain the same grep scan and draining
tail, strip the fixed marker wrapper with Bash parameter expansion, and assign
the caller's variable directly. This removes sed without introducing another
command substitution around the result. Clear the destination before reading
so a missing or unmatched log cannot reuse a previous stall name.

This is benchmark instrumentation only. Node code, consensus, validation,
optional acceleration, peer/request scheduling, databases and verdict
thresholds are unchanged. No end-to-end IBD speedup is established here.

Baseline: `agent/worldstream-ibd-20260918` at
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including the pre-existing
uncommitted Worldstream changes. Stopwatch SHA-256 before this slice:
`059a2419f7298c9df2aa85bfa0af0b39ea45d4bf04959bf0ea42ed23b24aeadb`.
After this slice:
`14a752ad8412d510bdf6a13d61d38e148db5053995e4b644b50783f3bcbda44c`.
The slice comprises only `log_named_park`, its two callers, the added
selftest invocation, `tools/scripts/stopwatch_park_log_selftest.sh` and this
note. All other pending work is outside the slice.

Run `bash tools/scripts/stopwatch_park_log_selftest.sh --bench` to compare
the original pipeline, retained as a reference, with the production function.
Both are called the way their respective harness versions consume a result.
On Linux x86_64 and Bash 5.2.21, three sequential trials of 1,000 reads of a
small synthetic parked-boot log produced:

| Measurement | Original | Changed |
|---|---:|---:|
| External tools per observation | 3 | 2 |
| Wall seconds, trial 1 | 4.160 | 3.765 |
| Wall seconds, trial 2 | 4.228 | 3.768 |
| Wall seconds, trial 3 | 4.300 | 3.827 |
| Median wall seconds | 4.228 | 3.768 |
| Median user + system CPU seconds | 8.463 | 5.891 |

Median observer wall time fell about 11% and CPU time about 30%. This is
approximately 0.46 ms per read on this fixture, not a time-to-tip claim.
Executable/filesystem caches were warm; host load was uncontrolled. The
benchmark launches no node and uses no network or production datadir.

Ten compatibility cases compare values and exit status with the original
pipeline: missing, empty and marker-free logs; single and repeated markers;
multiple markers on an unterminated line; empty and literal names; an
incomplete final marker; and a stream larger than a pipe buffer containing
binary bytes outside the markers. The process budget is deterministic.
Mutants that retain a stale result or add back an external parser both fail.
The full cold-start stopwatch selftest, artifact-symmetry mutation suite and
stopwatch evidence-judge selftest pass.

Shell syntax, whitespace, shell-host assumptions, discarded-status,
pipefail-status-pipe, no-API-keys, no-Python, no-warning-suppression and
architecture checks pass. The core seal verifies 554 files and 80 sections;
its exported root mirror matches and there is no diff under `core/`. This
shell-only slice changes no compiler inputs. No logs, generated files,
binaries, credentials or temporary benchmark outputs belong to the slice.

Full `make lint` is incomplete: it exceeded a 45-second bound during build
prerequisites. Focused checks do not claim that umbrella passed. Publication
is not complete: fetching the development branch cannot write
`.git/FETCH_HEAD` (read-only filesystem), and the origin query fails on
GitHub DNS. `origin/main` is absent. No commit, push or remote-SHA equality
is claimed. Continue only on `agent/worldstream-ibd-20260918`; preserve the
unrelated staged and unstaged work when preparing the eventual commit.
