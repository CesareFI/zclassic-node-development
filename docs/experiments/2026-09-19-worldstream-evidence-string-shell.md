<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: remove the extra shell from evidence string emission

Baseline HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The checkout already contained extensive
Worldstream edits. This experiment compares the working library immediately
before this slice with the same library after changing only `evidence_jstr`.
In particular, the earlier conversion of `evidence_json_escape` to Bash
substitutions is held constant in these timings.

The evidence library feeds the tip-agreement and SLO observers used during
sync. Its complete-string wrapper used command substitution for every string,
starting a child shell even though the escaping helper used only builtins.
The wrapper now streams the opening quote, escaped bytes and closing quote.

Linux x86_64, AMD EPYC 7402P, Bash 5.2.21; warm ordinary filesystem caches,
ambient host load, local fixtures only:

| Measurement | Before | After |
|---|---:|---:|
| Extra shells per complete string | 1 | 0 |
| 500 fixed 41-byte literals, wall | 0.584 s | 0.027 s |
| Same loop, user + system CPU | 0.638 s | 0.027 s |
| Ten full 12-cluster tip observer fixtures, wall | 3.241 s | 3.115 s |
| Same observer fixtures, user + system CPU | 4.632 s | 4.496 s |

The observer difference is small and subject to noise. These are observation
costs, not measured IBD or time-to-tip gains. No chain or real peer was used.

Reproduce the byte checks, process budget and optional benchmark with:

```sh
bash tools/scripts/evidence_jstr_process_selftest.sh --bench
bash tools/scripts/test_tip_agreement_evidence.sh --only observer
```

The first command accepts a final library path for before/after comparison.
The new regression passes all byte checks on the previous wrapper, then fails
because its instrumented escaping helper observes a different `BASHPID`.
With the change it passes, including omitted/empty arguments, whitespace,
quotes, backslashes, UTF-8 and every non-NUL byte. Applying only the wrapper
change to the HEAD library also passes; this fix does not require the earlier
uncommitted escaping optimization. The test joins `make evidence-selftest`.

All twelve directly invoked evidence/SLO shell selftests and the complete
tip-agreement recorder/judge suite passed. Bash syntax and both staged and
unstaged `git diff --check` passed. Direct architecture, shell-host-assumption,
pipefail-status-pipe and discarded-status lint gates passed (4/4).
The node build and Make-based lint/test
attempts were interrupted after prerequisite work stalled; the node build
reported that Tor submodule registration could not write `.git/config`.
These attempts are not passing build or full-lint evidence.

This slice owns only the wrapper, its new selftest, the one-line Makefile
registration and this report. It changes no consensus, validation, optional
acceleration, peer scheduling, database behavior or production state. No
credentials, generated files, binaries or raw benchmark output belong in the
slice. Existing dirty changes remain separate and must not be swept into its
commit.

Publication remains blocked: `.git` is read-only, fetching cannot write
`FETCH_HEAD`, and read-only remote SHA lookup fails to resolve GitHub. No
commit, push or verified remote SHA is claimed. The branch remains unchanged.
