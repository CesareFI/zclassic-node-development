<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: stop rescanning witnessed onion bootstrap milestones

Scope: bootstrap performance instrumentation in
`tools/scripts/onion_pair_watch.sh`. This changes the isolated observer only.
It does not change consensus, validation, peer scheduling, storage, optional
acceleration, or any production node. No live peers or datadirs were used.

Baseline source: `c1f7863d098e1efaa8deba240c580ae0559312a5`.
This three-file slice was already staged when the continuation run began;
the run requalified it without including the other staged or unstaged work.
The initial development-branch fetch succeeded; origin has no `main` ref.
Local HEAD and `origin/agent/worldstream-ibd-20260918` both identified the
baseline. The final fetch and publication were blocked as described below.

## Measured problem

`observe_stages` repeatedly searched logs for milestones whose boolean flags
were already true. These flags already remain true through log rotation and
through later misses. Five successful log searches per completed observation
could therefore do no useful work. When a milestone occurs late in a large
log, these searches also repeatedly consume its prefix.

Each log predicate now runs only until its corresponding event is observed.
Missing events keep their existing search patterns and fallback paths. RPC
sampling continues even when every log milestone has been observed.

Host: Linux 6.8.0-139-generic, x86_64, AMD EPYC 7402P, 48 logical CPUs;
Bash 5.2.21 and GNU grep 3.11. Synthetic local fixtures, warm filesystem
caches, no node workload or network. The fixture has four logs, each with a
128 MiB non-NUL prefix plus milestone lines. The benchmark invokes 100
completed-stage observations without an RPC cookie, isolating log cost.

| Observation | Baseline | Changed |
|---|---:|---:|
| Log searches per completed poll | 5 | 0 |
| 100 polls, wall seconds | 14.399 | 0.008 |
| User CPU seconds | 4.883 | 0.005 |
| System CPU seconds | 9.586 | 0.003 |

These are single-run observer measurements, not end-to-end IBD or time-to-tip
evidence. The deterministic regression checks search count, not a timing
threshold. An initial early-marker-only experiment found that GNU grep already
stops early when stdout is `/dev/null`; no grep-flag change was justified.

## Reproduction and validation

```bash
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/onion_pair_watch.sh > /tmp/onion_pair_watch.before.sh
bash tools/scripts/onion_pair_log_selftest.sh --bench /tmp/onion_pair_watch.before.sh
bash tools/scripts/onion_pair_log_selftest.sh --bench
bash tools/scripts/onion_pair_watch.sh --selftest
```

The baseline command intentionally exits 1 at the final zero-rescan assertion
after printing its benchmark. The changed benchmark passes 29 cases. The
ordinary 26-case regression is called by the existing probe self-test, already
reachable through `make check-onion-pair-watch`.

Coverage includes missing/empty logs, binary and unterminated lines, invalid
patterns, descriptor intent versus successful upload, node-log fallback,
partially observed stages, later arrivals, both circuit-ready log paths, log
rotation, and continued RPC observation after all log flags are true.

The broader probe self-test also passed in an isolated directory using the
committed `isolated_node_env.sh` and `port_probe.sh`, proving this slice does
not depend on the checkout's unrelated edits to isolation helpers.

Passed: Bash syntax checks, pipefail-status-pipe, discarded-status,
shell-host-assumptions, architecture-tree, and `git diff --check`.
No compiled sources or generated interfaces changed. Full `make lint` was
attempted and interrupted during node build prerequisites after reporting
missing Tor archives; it did not produce a full lint verdict. No validation
gate or baseline was relaxed. Temporary logs and benchmark files remain
outside the commit.

## Publication status

The continuation run reproduced the baseline failure, passed the 29-case
changed benchmark, and passed the broader probe self-test against committed
isolation helpers. It reran the shell and architecture gates listed above,
including both shell-status gates' self-tests. Full lint was again interrupted
during build preparation without a verdict; it is not claimed as passing.

The final fetch could not write `.git/FETCH_HEAD`. A path-limited commit of
exactly these three files failed because `.git/index.lock` could not be created
on the read-only filesystem. No commit or push was made, and no remote SHA
verification is claimed. The branch remains `agent/worldstream-ibd-20260918`.
Publication requires a supervisor run with authorized Git metadata writes;
the unrelated pending work must remain outside that commit.

Remaining measurement: pending milestones still require searches, and RPC
sampling still launches five JSON queries per observation. Measure those
costs separately before selecting another improvement. A real time-to-tip
comparison remains unmeasured by this fixture.
