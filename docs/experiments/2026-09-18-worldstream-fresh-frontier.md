<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: fresh-boot frontier observation cost

Scope: the `rpc_frontier` observer in `tools/scripts/fresh-boot-proof.sh`.
Baseline HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. Existing dirty work, including this script's
separate log-maximum optimization, is preserved and is not part of this slice.

The reader started a `printf | grep -q` pipeline on every RPC observation.
With an early matching line and a response larger than the pipe buffer, grep
closed the pipe while printf was still writing. With pipefail enabled, that
valid observation triggered retries instead of returning immediately. A single
successful observation followed by empty replies was lost entirely. The manual
harness normally sets only nounset; this retry defect requires pipefail, which
Bash can inherit through exported SHELLOPTS. The process cost exists in either
configuration.

The change uses Bash's built-in literal substring match. It retains the same
quoted `hstar` match, unchanged returned bytes, four-attempt budget, one-second
backoff, and final-response fallback. It adds no stronger claim about the
validity of the response. No node, consensus, validation, scheduling, database,
or acceleration configuration changes are included.

## Fixture evidence

Measured on Linux x86_64, kernel 6.8.0-139-generic, Bash 5.2.21. Local generated
responses, warm host caches, no network or node. The regression sources only
the reader function, never the harness's datadir or process-launch code.
RPCs use a fixture counter; sleep records requested backoff without waiting.

| Observation | Before | After |
| --- | --- | --- |
| Large early match, pipefail enabled | 4 RPCs / 4 s requested backoff | 1 RPC / 0 s |
| Large early match followed by empty, pipefail enabled | valid response lost | exact response retained |
| Busy or empty response, either mode | 4 RPCs / 4 s requested backoff | unchanged |
| External matchers across 16 fixture cases | 46 | 0 |
| 200 small fixture reads, wall time | 1.752 s | 0.473 s |

Wall times are single observations, include fixture overhead, and are not a
live time-to-tip result. The deterministic gates check calls, backoff, exact
response bytes, and matcher count. Both pipefail modes cover small responses,
early and late matches around 1 MiB of padding, one-shot responses, busy
responses, similarly named keys, and missing data. The pre-change reader fails
the regression; the changed reader passes all 16 cases.

Reproduce the comparison without launching a node:

```bash
baseline=$(mktemp /tmp/z23-fresh-frontier-baseline.XXXXXX)
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/fresh-boot-proof.sh > "$baseline"
bash tools/scripts/fresh_boot_frontier_selftest.sh --bench "$baseline" # expected failure
rm -f "$baseline"
bash tools/scripts/fresh_boot_frontier_selftest.sh --bench
```

Validation: Bash syntax checks, the 18-case fresh-boot log-reader regression,
both sibling stopwatch frontier readers, all 11 hermetic fresh-boot-weld
assertions, pipefail-status lint, live-datadir isolation lint, no-Python lint,
and `git diff --check` pass. The core tree is unchanged from HEAD. New files
contain test source and this report only.

The node build cannot complete here: required vendor dependencies are absent,
fetch/submodule Git metadata writes are refused as read-only, and github.com
cannot resolve. Full compiled proof and full lint prerequisites therefore
remain unavailable. Fetch and remote
SHA verification are also blocked. The cached tracking SHA equals the baseline
HEAD; that is not a fresh remote observation or evidence of publication.
Staging the source hunk also fails because `.git/index.lock` is read-only.
The two new files were staged successfully earlier, but the source hunk and
latest report remain working-tree changes. No slice commit or push was made.

The next live measurement remains fresh-datadir time to independently validated
tip with stage costs. This fixture establishes a cheaper and more reliable
observer only; it does not establish a chain synchronization speedup.
