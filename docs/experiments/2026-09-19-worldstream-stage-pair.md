<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream paired frontier observation

Branch: `agent/worldstream-ibd-20260918`. Base commit:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. The working tree already contained
extensive pending Worldstream changes. This slice changes only the frontier
cursor helper, its phase-observer caller and selftest invocation in
`tools/scripts/cold_start_to_tip_stopwatch.sh`, adds
`tools/scripts/stopwatch_stage_pair_selftest.sh`, and adds this note.
Earlier staged work is preserved byte-for-byte.

The phase observer parsed the same captured frontier response twice per poll,
once for `header_admit` and once for `body_persist`. Its existing awk helper
now optionally returns a second cursor in the same pass. The caller reads the
pair together. Each missing cursor retains its independent `-1` sentinel.
Single-stage callers retain the same output. Compact-record parsing, duplicate
record selection, phase thresholds, timestamps and verdict logic are unchanged.

The new regression extracts and runs the actual helper and `phase_observe`
with fixed responses and a fixed observation time. Unrelated RPCs are stubbed;
there is no node, network, wallet or production datadir. Both baseline and
candidate pass the boundary assertions; only the baseline fails the new
one-parser budget. Missing, malformed, duplicate, reordered and large records
are covered. A mutation that substitutes the first cursor for the second
fails the body-only boundary case. Pair order, repeated stage names and
independent missing cursors are checked directly too.

Three alternating runs of 500 phase observations, Linux x86_64, Bash 5.2.21
and GNU Awk 5.2.1, with warm tool/filesystem caches and ambient host load:

| Measurement | Before | After |
|---|---:|---:|
| Cursor-parser processes per phase observation | 2 | 1 |
| Wall time, run 1 | 6.188 s | 3.521 s |
| Wall time, run 2 | 6.162 s | 3.540 s |
| Wall time, run 3 | 6.037 s | 3.528 s |
| Median wall time | 6.162 s | 3.528 s |

This is about 43% less fixture observer time, not an end-to-end IBD or
time-to-tip speedup. Timing is informational; process count and unchanged
boundary decisions are the deterministic assertions. Later runs overlapped
other local validation work; these are not controlled host-wide benchmarks.

Reproduce with:

```bash
bash tools/scripts/stopwatch_stage_pair_selftest.sh --bench
bash tools/scripts/cold_start_to_tip_stopwatch.sh --selftest
```

The first command accepts a saved baseline script as its final argument.
The measured baseline script SHA-256 is
`95d9c13d03f764868d1f16d8a0d3dbad8f83c70026c3b60263dfb4e7ba381f48`;
the resulting script SHA-256 is
`d4f37e624963a661b021521042114099261bb09c743673c3e5b87eec8fc59bf0`.
The baseline includes earlier pending observer changes, so checking out the
base commit alone does not reproduce these two-parser baseline timings.

Validation passed: focused pair regression, existing single-stage regression,
full stopwatch selftest, artifact-symmetry mutation suite, evidence-judge suite,
Bash syntax checks, architecture-tree, shell-host-assumptions,
pipefail-status-pipe, consensus-parity and core-seal-root-mirror checks, plus
`git diff --check`. Direct seal verification matches all 554 files and 80
sections. Git-index-based gates do not include the new untracked test; its
syntax and behavior were checked directly. ShellCheck is unavailable. No
compiled source changed. Full `make lint` exceeded a 45-second bound during
build setup and is not claimed green.

Consensus, mandatory validation, optional acceleration policy, peer scheduling,
database tuning and runtime behavior are unchanged. Only benchmark observation
and its regression change. Temporary fixtures, benchmark output and logs stay
outside the proposed source changes.

Publication is incomplete. Repeated `git fetch origin main` attempts fail
because `.git/FETCH_HEAD` is read-only; querying the development branch on
origin fails because `github.com` cannot resolve. The existing `/tmp` checkout
also uses Git metadata outside the writable roots. No upstream integration,
commit, push or remote-SHA equality is claimed. The branch remains unchanged.
