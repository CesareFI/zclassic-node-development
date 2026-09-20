<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bound repeated parsing in sync diagnostics

Owned surface: the read-only `tools/scripts/debug_bundle_triage.sh` report.
The baseline file is unchanged from commit
`c1f7863d098e1efaa8deba240c580ae0559312a5`. No node, peer scheduler, database,
consensus predicate, validation path, or acceleration policy changes.

The triage report helps identify an IBD blocker from a captured debug bundle.
It previously supplied the entire bundle to `jsonq` for every displayed field.
An unrelated large dumper therefore increased the cost of every frontier,
blocker, and supervisor query. A synthetic 1,049,820-byte bundle reproduced
55 full-document parser inputs, totalling 57,740,045 bytes.

The change extracts the five displayed JSON sections once from the validated
in-memory snapshot. Field queries use those exact fragments. Metadata queries
still use the original snapshot. Missing sections remain distinct from JSON
null; the original document must still pass complete JSON validation.

Measured on Linux x86_64, AMD EPYC 7402P, with GCC 14.2.0, C23, `-O2`, and
the unchanged in-tree `jsonq`/`zjsonp`/`zutf8` sources. Inputs and binaries lived
in temporary directories. There were no network requests, production data,
node processes, or cache flushes in the fixture. Warm before/after batches ran
sequentially; timings are host observations, not enforced thresholds.

| Observation | Before | After |
| --- | ---: | ---: |
| Parser input bytes per large-bundle report | 57,740,045 | 10,511,344 |
| Five warm reports, wall seconds | 7.556 | 3.436 |

Parser input fell 81.8%; measured report wall time fell 54.5%. This measures
diagnostic overhead only. It does not establish an end-to-end IBD speedup or
time-to-tip acceptance.

Reproduce with a built `jsonq`:

```sh
JSONQ=/path/to/jsonq TRIAGE_BENCH=1 \
  bash tools/scripts/debug_bundle_triage_selftest.sh
```

The optional positional argument selects an older triage script; the baseline
fails the deterministic limit of 16 bundle lengths. Set `TRIAGE_REFERENCE`
to an older script to compare full report bytes for populated, missing,
error-bearing, and null sections. The regression also checks escaped strings,
frontier numbers, blocker details, the five-blocker display limit, multiple
supervisor children, trigger metadata, and malformed/incomplete bundle refusal.
Large and compact equivalent bundles must render identically.

Validation: regression and reference comparison passed using both GCC 14 and
Clang 20 builds of the existing parser, compiled with `-Wall -Wextra -Werror
-pedantic`. Bash syntax and focused pipefail, discarded-status, shell-host,
no-Python, and architecture lint gates passed. Public-build Tor preparation
reported a read-only `.git/config` error. The build and aggregate lint attempts
then made no further visible progress and were bounded/interrupted; no public-node
build, full lint, chain replay, or live sync acceptance is claimed.

The continuation reran the baseline failure and output-equivalence regression
using the committed `tools/jsonq.c`, independent of the unrelated parser edit
in this checkout. The table records that rerun. Fetching the development
branch is blocked by read-only `.git/FETCH_HEAD`; the earlier `origin/main`
fetch found no remote `main` ref. Remote inspection also encountered DNS failure.
The three-path `git commit --only` attempt failed creating `.git/index.lock`
on the read-only filesystem. No commit or push was produced, and the remote
SHA could not be verified. The branch remains `agent/worldstream-ibd-20260918`.

Existing staged and unstaged Worldstream work was preserved separately. This
slice contains only the report change, its isolated regression, and this record.
