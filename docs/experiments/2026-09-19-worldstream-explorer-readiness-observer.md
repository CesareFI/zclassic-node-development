<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream explorer-readiness observation cost

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Host: Linux x86_64,
GCC 14.2.0, Bash 5.2.21. The checkout contained extensive staged and unstaged
Worldstream work before this slice. The baseline is that working-tree source,
not the clean HEAD. Earlier work is preserved.

The fresh-sync benchmark launched Bash and grep on every explorer-readiness
observation. The observer now reads curl's response in C using a 4,108-byte
buffer, retaining enough overlap to recognize a marker across read boundaries.
After a match it still drains the body and requires a successful transfer and
read. The two-second curl deadline, endpoint, readiness marker, milestone
timestamps, and completion criteria remain unchanged.

Three warm-tool/cache fixture runs of 100 observations with a one-MiB response:

| Measurement | Before | After |
|---|---:|---:|
| Wall time, run 1 | 1.196759 s | 0.393512 s |
| Wall time, run 2 | 1.205210 s | 0.398443 s |
| Wall time, run 3 | 1.192515 s | 0.395388 s |
| Median | 1.196759 s | 0.395388 s |
| Extra Bash/grep invocations per observation | 2 | 0 |

The median fixture observer cost fell about 67%. The curl stand-in produces
bytes locally; this does not measure network latency, real GUI responsiveness,
or end-to-end IBD/time-to-tip improvement. The underlying shell used by `popen`
and the curl process remain. No node, peer, credentials, wallet, or production
datadir participates.

The regression extracts the production function and tests 20 observations:
markers at either end, every split across its read boundary, absent/empty/
truncated markers, a newline interrupting the marker, and a failed transfer
after emitting a full one-MiB body containing the marker. The original function
passes these value checks but fails the deterministic process budget with 40
extra tool invocations; the replacement passes with zero. Timing is reported,
never used as an acceptance threshold. The regression is wired into the
existing `bench-fresh-sync-selftest` target.

```bash
bash tools/scripts/bench_fresh_sync_readiness_selftest.sh --bench --analyze
# Pass a saved pre-change C source for the A/B run (process-budget failure expected):
bash tools/scripts/bench_fresh_sync_readiness_selftest.sh --bench /tmp/before.c
```

Measured baseline SHA-256:
`43d0dfd7e2995d1722aefed5e06ed90972c22da43a3506d64e8310acd9e96217`.
Final C source SHA-256:
`081a5905a7a719b7fe9656eee7fb57085e6aed06724eb6a885cac77934184334`.

Validation:

- Focused regression compiled as C23 with `-Wall -Wextra -Werror -pedantic`
  and GCC `-fanalyzer`: pass.
- Existing HTTP-deadline, command-output and explorer-size regressions with
  GCC analysis: pass. Silent/partial transfers still fail around two seconds.
- Existing phase-log, completed-log, startup, height-demand and outcome/grace
  regressions: pass when run directly.
- Existing timing regression: identical failure before and after this slice
  (completion 19 seconds versus expected 21). Its assertion remains unchanged.
- Full benchmark executable builds with the target's compiler flags. Existing
  unchecked `system` and copy-command truncation warnings remain outside this
  slice; strict compilation and analysis above cover the changed observer.
- Architecture, consensus-parity (including its selftest), core-root mirror,
  pipefail-status and shell-host-assumption checks: pass. The new untracked
  script is outside index-based lint coverage; its Bash syntax and execution
  were checked directly. ShellCheck is unavailable.
- Direct core-seal verification: all 554 files and 80 sections match.
- `make -j4 lint` did not finish within a 60-second bounded attempt; no full
  lint pass is claimed. `git diff --check`: pass.

Only the benchmark observer, one test-target entry, its regression, and this
report belong to this slice. The exact delta against the saved working-tree
baseline was reviewed. No generated files, binaries, logs, credentials or
temporary outputs belong to the proposed change. Consensus and independent
validation are unchanged; optional acceleration remains optional. No Hetzner
scheduling, database, or node-runtime surface changed.

Publication is incomplete. Fetching the development branch fails because
`.git/FETCH_HEAD` is on a read-only filesystem. Independent remote lookup
also fails because the origin host does not resolve. No commit or push was
made, and remote SHA equality was not verified. The existing timing failure
and incomplete full lint also prevent claiming publication acceptance.
Temporary baselines, build output and a slice-only patch are under
`/tmp/worldstream-explorer-readiness/` and are not repository artifacts.
