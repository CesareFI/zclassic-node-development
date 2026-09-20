<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream stopwatch judge scalar-reader cost

Branch: `agent/worldstream-ibd-20260918`. HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`. Linux x86_64, Bash 5.2.
The baseline includes the pending Worldstream edits present on entry.
This slice changes only `fld_num` and `fld_str` in
`tools/scripts/stopwatch_evidence_judge.sh`, adds their standalone regression,
wires it into `stopwatch-judge-selftest`, and adds this report.

Each scalar extraction in the time-to-tip evidence judge launched three
external tools: grep, head and sed. The judge reads timestamp, verdict,
artifact identity and fixture fields this way. Bash regular-expression
matching now extracts the first eligible compact field without these tools.
Missing fields still return status 1; empty strings remain successful reads.
Literal newlines cannot join string values across lines. This preserves the
existing limited field-reader convention, including numeric-prefix matching;
it does not add general JSON parsing or change acceptance criteria.

The isolated fixture reads 500 timestamp/verdict pairs with ordinary warm
filesystem caches and ambient host load:

| Measurement | Baseline | Changed |
|---|---:|---:|
| External parsing processes | 3,000 | 0 |
| Wall seconds | 5.323 | 1.196 |
| User seconds | 1.880 | 0.337 |
| System seconds | 9.623 | 0.964 |

Timings include the fixture's process-count instrumentation and Bash command
substitutions, which remain. Only the process budget is asserted; elapsed
time is informational. This measures evidence-reporting overhead, not node
synchronization, GUI responsiveness or end-to-end IBD improvement. No node,
network, wallet or production datadir participates.

Reproduce with:

```bash
bash tools/scripts/stopwatch_judge_fields_selftest.sh
# Optional argument: a saved baseline stopwatch_evidence_judge.sh.
bash tools/scripts/stopwatch_evidence_judge.sh --selftest
bash tools/lint/check_stopwatch_skip_detector.sh
```

Twenty scalar cases pass on both versions, covering signed/zero/large
numbers, first eligible duplicates, multiple lines, missing values, empty
strings, whitespace, literal backslashes and incomplete strings. The baseline
then fails the zero-process budget; the changed version passes it. A mutation
returning success for missing fields is rejected by the regression. The full
judge selftest and skip-detector suite pass, including stale evidence,
below-checkpoint and lagging fixtures, wrong/missing artifact bindings,
skip alarms, and bounded oracle-tail cases.

Bash syntax, discarded-status, pipefail-status, shell-host-assumption,
architecture-tree, consensus-parity and core-seal-root-mirror checks pass.
The new untracked regression is outside index-based shell lint, and was
parsed and run directly. ShellCheck is unavailable. `make -j4 lint-fast`
and `make stopwatch-judge-selftest` were interrupted during setup without
reaching a verdict; the individual shell tests above completed directly.
No aggregate lint or node-build success is claimed.

The exact slice diff was inspected and `git diff --check` passes. Existing
staged work is unchanged. No node, consensus, independent-validation,
optional-acceleration, peer-scheduling, database or runtime code is changed.
Only source, test and documentation files belong to this slice; benchmark
output and temporary copies remain under `/tmp/worldstream-judge-fields/`.

Baseline judge SHA-256:
`65728316998fea82117790a8b983443c6047f2e45ffabd4de4daba90ea46858e`.
Changed judge SHA-256:
`cd031c394210559ae85995936f798e0f99c6e44d477d1038325bbd78e256fedf`.

Publication remains incomplete. Fetch cannot write `.git/FETCH_HEAD` because
Git metadata is read-only; querying origin fails GitHub DNS resolution.
No upstream integration, commit, push or remote-SHA equality is claimed.
The required branch remains unchanged. Required aggregate gates and
publication remain outstanding.
