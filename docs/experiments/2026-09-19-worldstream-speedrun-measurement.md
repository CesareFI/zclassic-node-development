<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: distinguish startup timing from time to tip

Scope: `tools/speedrun.c` reporting and an isolated regression fixture. No
consensus, validation, peer scheduling, database or node runtime changes.

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`. This checkout already
contained substantial unrelated work; none is part of this slice.

## Measurement defect

The speedrun clock spans `app_context_defaults()` and `app_init()`. The latter
starts services and can return while catch-up or background validation is
incomplete. Nevertheless, the tool printed `TOTAL (zero to tip)` and `SUCCESS`
when startup returned true. It never observed a captured peer tip, durable
catch-up, or sovereign validation completion. That output cannot identify the
end-to-end IBD bottleneck or support a time-to-tip comparison.

The regression compiles the actual tool entry point against the repository's
real headers. It substitutes the boot boundary, clock and directory creation:
no node, network, datadir or wallet is opened. Two monotonic clock reads differ
by exactly 2,345 ms; boot returns either true or false without observing any
sync milestone. On the baseline, the successful boot prints a 2,345 ms
zero-to-tip success and the regression fails. This is a deterministic
measurement witness, not a measured network IBD duration.

## Change and validation

The report now labels the interval `Startup attempt`, distinguishes startup
completion from failure, and prints `NOT MEASURED` for both time to tip and
sovereign validation. Existing startup configuration, clock boundaries and
exit codes are preserved. Optional acceleration and independent validation
are unchanged.

Reproduce the regression with:

```bash
bash tools/scripts/speedrun_measurement_selftest.sh
```

Pass an absolute path to an older `speedrun.c` as its first argument to replay
the failing witness. Both startup outcomes are exercised; each must retain
the exact duration while withholding unobserved sync milestones.

Validation on Linux x86_64 with GCC 14.2.0:

- Baseline regression: fails on the false zero-to-tip claim.
- Corrected regression: passes for successful and failed startup.
- C23 compilation with `-O2 -Wall -Wextra -Werror`: passes.
- GCC `-fanalyzer` compilation of the complete tool: passes.
- AddressSanitizer and UndefinedBehaviorSanitizer fixture: passes with
  `ASAN_OPTIONS=detect_leaks=0`. LeakSanitizer cannot run under this execution
  environment's ptrace boundary; leak checking is not claimed.
- Shell syntax, architecture tree, discarded-status and pipefail-status gates,
  including both shell gates' own selftests: pass.
- `git diff --check`: passes.

Full `make lint` and an attempted Make-driven fixture run did not reach their
recipes during build preparation and were interrupted. They are not reported
as passing. No full-node build or live-chain acceptance is claimed for this
reporting-only change. The regression remains directly runnable without those
build prerequisites.

This slice fixes evidence, not sync throughput: it claims no IBD speedup.
Next measurement needs a captured peer tip and a durable catch-up observation,
with assisted readiness and sovereign completion recorded separately.
