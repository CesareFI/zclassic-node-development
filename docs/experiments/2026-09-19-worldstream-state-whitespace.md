<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream formatted RPC state observation

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. Existing staged and unstaged changes are
preserved. This slice changes only the benchmark string-field reader and
extends the existing outcome regression, plus this report.

The cold-start benchmark recognized `"state":"at_tip"` but missed legal JSON
whitespace before or after the colon. A responding, ready node could therefore
remain `unknown` to the observer until its 1800-second deadline. This is a
measurement defect reproduced with fixtures, not an observed live IBD delay.

The reader now skips the four JSON whitespace characters around the colon,
still requiring a colon and a quoted value. An earlier string value equal to
the key does not hide the actual field. No decoder, dependency or subprocess
is added. The reader remains limited to the benchmark's plain string fields;
it is not a general JSON validator or escaped-string decoder.

The regression compiles the production polling loop and result path with a
deterministic clock, successful explorer fixture and a 30-second deadline.
Starting at elapsed second 10 with an at-tip response:

| Input | Before | After |
|---|---|---|
| Compact JSON | Completes at second 16, four polls | Same |
| Space after colon | Times out, 11 polls | Completes at second 16, four polls |
| Space before colon | Times out, 11 polls | Completes at second 16, four polls |
| Mixed space/tab/CR/LF separators | Times out, 11 polls | Completes at second 16, four polls |
| Missing colon or unquoted value | No completion | No completion |
| Earlier `"label":"state"` value | Completes | Completes |

These are simulated observation times, not real synchronization speedups.
No node, network, wallet or production datadir participates. Completion,
explorer, consecutive-tip and deadline requirements are unchanged.

Reproduce with:

```bash
bash tools/scripts/bench_fresh_sync_outcome_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_height_selftest.sh --analyze
```

The measured pre-change working-tree benchmark SHA-256 was
`081a5905a7a719b7fe9656eee7fb57085e6aed06724eb6a885cac77934184334`;
the final benchmark SHA-256 is
`06435f68965bc282ccd373a8bd9fb32d5a9166fb2b4812e670f3774bab82ec37`.
The baseline includes earlier pending work, so HEAD alone is not that baseline.
Passing a saved baseline source as the test's final argument reproduces the
three failing whitespace cases. The same regression passes all 19 scenarios
after the change, with C23 warnings-as-errors and GCC static analysis.

Nine of ten surrounding benchmark selftest scripts pass: phase log, completed
log, startup, command output, HTTP deadline, page size, explorer readiness,
outcome and height demand. The timing script fails its existing expected
completion value of 21 seconds versus actual 19 seconds on both the saved
baseline and changed source; this slice leaves that assertion untouched.
Whole-tool `-Wall -Wextra -Werror` compilation fails on the same pre-existing
ignored `system` results and copy-command truncation warnings in both sources.
Focused compiler/static checks pass. Shell syntax, architecture-tree,
pipefail-status, discarded-status, shell-host-assumption, consensus-parity,
core-seal mirror and whitespace checks pass. The core seal verifies all 554
files and 80 sections. No full lint or full-node acceptance pass is claimed.

The attempted public build could not initialize the absent Tor submodule
because Git metadata is read-only; the bounded attempt was stopped. Fetch also
failed on read-only `.git/FETCH_HEAD`, and remote branch lookup failed because
`github.com` did not resolve. No commit or push was performed, and no remote
SHA equality was established. The staged diff is byte-identical to its initial
snapshot. Fixtures, binaries and logs remain under `/tmp`, outside this slice.
Consensus, cryptographic validation, acceleration policy, scheduling, databases
and node runtime are unchanged.
