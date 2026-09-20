<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: measure the startup budget with elapsed time

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.
Owned surface: the fresh-sync benchmark startup observer and its regression.

The startup timeout counted 600 sleeps as 300 seconds. An interrupted sleep
can return early, so that counter could discard a healthy startup before its
budget expired. Conversely, log-observer work extended the budget. Progress
messages also followed poll count instead of their advertised ten seconds.

The observer now uses its existing monotonic clock for both deadlines. Sleep
requests remain at most half a second and are shortened at the deadline.
Cookie handling, child-exit refusal and EINTR retries for child observations
are unchanged. The deadline includes observation costs but cannot preempt a
blocking filesystem operation or an OS scheduling delay.

The regression compiles the actual startup function, with an inert cookie,
simulated clock, interrupted sleeps and a live-child stub. It performs no node,
network, wallet or canonical-datadir operations. On Linux x86_64, GCC 14.2,
`-std=c23 -O2 -Wall -Wextra -Werror -pedantic`:

| Scenario | Entry source | Candidate |
|---|---|---|
| No cookie, ordinary sleeps | Timeout at 300 s | Same |
| Sleeps interrupted after 125 ms; cookie at 120 s | False timeout at 75 s | Ready at 120 s |
| Same interruptions, no cookie | Timeout at 75 s | Timeout at 300 s |
| Each progress observation costs 250 ms; no cookie | Timeout at 307.25 s | Timeout at 300 s |
| Cookie appears at the 300 s boundary | Accepted | Same |

Interrupted polls previously printed progress every 2.5 seconds; the candidate
retains at least ten seconds between progress observations. These are
deterministic measurement-correctness results, not measured end-to-end IBD
speedups or a claim about signal frequency on the host.

Reproduce with:

```sh
bash tools/scripts/bench_fresh_sync_startup_budget_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_startup_selftest.sh --analyze
make bench-fresh-sync-selftest
```

All pass. The new test accepts an optional source path; `--baseline` prints
observations without requiring candidate behavior. Without that option, the
entry source fails the interrupted-startup regression. The extracted function
also passes GCC `-fanalyzer`. Shell syntax, architecture-tree, pipefail-status,
discarded-status, shell-host-assumption and whitespace checks pass. The four
lint scripts were run directly after their combined Make invocation stalled
in initialization and was interrupted.

Broader qualification remains incomplete: `timeout 50 make lint-fast` expires
in initialization. Strict full-translation-unit compilation fails identically
before and after on five ignored `system` return values and two potentially
truncated copy commands. No assertion, warning policy or validation predicate
was relaxed to obtain a pass.

This slice changes only the observer, adds its test to the existing Make
aggregate, and adds this note. Existing dirty work and the Git index are
preserved. No consensus, node runtime, optional-acceleration policy, custody,
peer scheduling or database behavior changes. No secrets, generated files,
binaries or benchmark output belong to the slice.

Entry benchmark source SHA-256:
`4b11cc0bcb5fe6ca41156049187e2bcd4ef077005a85e46a59e40ff233c22008`.
Entry copies and a slice-only patch are under `/tmp/worldstream-startup-budget/`.
Do not stage the entire already-dirty benchmark or Makefile as this slice.

Publication is blocked: fetching cannot write `.git/FETCH_HEAD`, staging cannot
create `.git/index.lock`, and `git ls-remote origin` fails GitHub DNS resolution.
`origin/main` is unavailable locally. No commit, push or remote-SHA verification
is claimed; the branch and HEAD remain unchanged.
