<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Cold-sync preflight: retain the absolute connect deadline

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5`.
Owned surface: `tools/fs_handshake_probe.c`, the cold-sync stopwatch's
standalone fixture-compatibility probe. No node scheduling or database changes.

The probe calculated its writable-wait timeout before opening and connecting
the nonblocking socket. Time consumed by setup or descheduling was therefore
added to the wait, even though the probe advertises one absolute deadline for
connect and handshake. Recalculate the remaining budget immediately before
waiting; if it has expired, close the socket and stop trying addresses.

## Reproduction and measured result

Run the deterministic regression without a node, resolver, or network:

```sh
bash tools/scripts/fs_handshake_probe_deadline_selftest.sh
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/fs_handshake_probe.c > /tmp/fs-probe-before.c
bash tools/scripts/fs_handshake_probe_deadline_selftest.sh /tmp/fs-probe-before.c
```

The fixture compiles the production connection helpers with real platform
socket types and substitutes the clock and socket operations. It assigns
750 ms to setup within a 1,000 ms budget and consumes the timeout supplied to
the writable wait. These are simulated milliseconds, not host wall timings.

| Observation | Before | After |
|---|---:|---:|
| Writable-wait timeout | 1,000 ms | 250 ms |
| Elapsed fixture time | 1,750 ms | 1,000 ms |

The baseline fails the remaining-budget assertion. The changed helper passes
that assertion and covers expiry before setup, expiry during setup, socket
cleanup, immediate and pending successful connections, pending connection
errors, multiple addresses, and the timeout cap.

## Validation and limits

- Regression compiled and passed with GCC 14.2, C23, `-O2 -Wall -Wextra
  -Werror -pedantic`.
- The full standalone probe built with the existing Makefile recipe's sources
  and strict compiler flags, linking the real handshake and crypto code.
  Usage and invalid-budget exit-code checks passed.
- GCC `-fanalyzer -fsyntax-only` passed on the full production probe.
- AddressSanitizer and UndefinedBehaviorSanitizer passed the regression.
  LeakSanitizer cannot run in this sandbox; that check is unobserved.
- All 32 `make lint-fast` gates passed in an isolated copy of the base plus
  this slice, using `ZCL_WINDOWS_ACCEPTANCE_GUARD_SCRATCH` for writable fixtures.
- Architecture, C23-only, and API-key scans passed; `git diff --check` passed.

This removes a deterministic source of preflight budget overshoot. It does
not measure end-to-end IBD, change handshake authentication, or guarantee a
hard wall-clock bound: synchronous name resolution and scheduler delays can
still consume time beyond the deadline. The regression does not exercise a
live peer. Independent Zclassic validation remains authoritative, acceleration
remains optional, and all consensus, core, and runtime sources are unchanged.
