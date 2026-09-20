<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: avoid source-tree enumeration before anchor resume

Branch: `agent/worldstream-ibd-20260918`. Base commit:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

`produce_anchor_snapshot.sh` ran recursive `du` over the source datadir on
every invocation, including resumes that reuse the existing work copy. It
also required twice the source size in free space on those resumes, despite
not making a new copy. The copy-space preflight now runs inside the existing
new-copy branch. Its threshold and refusal remain unchanged for new copies.
This removes source-file enumeration before a resumed optional anchor build.
It does not claim the resumed mint needs no additional disk space.

The producer was clean at entry. Its baseline SHA-256 is
`0a5d7cf284dd3f388d5fff8d75ee8d3bab8e4dc8b7a21840ddf29126a2262982`.
Only that script, the new `anchor_resume_preflight_selftest.sh`, and this
record belong to this slice. Existing staged and unstaged work is unrelated
and must not be included in its eventual commit.

## Reproduction and measurement

The regression executes the actual producer against private temporary
directories and an inert mint stub. It records `df`, `du`, and mint calls.
The baseline fails the resume assertion with `df, du, mint`; the candidate
performs only `mint`. Both intentionally report mint failure from stub exit
23; no snapshot or successful validation evidence is produced by the timing
fixture.

```sh
bash tools/scripts/anchor_resume_preflight_selftest.sh
bash tools/scripts/anchor_resume_preflight_selftest.sh --bench
# Optional final argument selects a saved baseline producer script.
```

Host: AMD EPYC 7402P, 24 cores / 48 threads; Linux 6.8.0-139-generic x86_64;
Bash 5.2.21; GNU coreutils 9.4. The benchmark creates 20,000 empty files in
100 directories and times 20 resumes, using real `du` and mocked `df`.
Fixture creation is outside timing. Filesystem caches are warm, ambient load
is uncontrolled, and no network or production datadir participates. Three
paired runs execute baseline before candidate:

| Wall seconds for 20 resumes | Run 1 | Run 2 | Run 3 |
| --- | ---: | ---: | ---: |
| Baseline | 2.267 | 2.248 | 2.244 |
| Candidate | 0.724 | 0.734 | 0.738 |

Median preflight/stub-run time falls approximately 67%, from 112.4 to 36.7 ms
per invocation. This is a synthetic helper-cost measurement, not measured
chain synchronization or time-to-tip acceleration. Actual source trees,
storage, cache state, and mint work will determine end-to-end impact.

## Validation and boundaries

Eight regression scenarios pass: existing-copy resume, low-space resume,
new-copy refusal below twice the source size, admission exactly at that
threshold, missing source, non-executable producer, missing snapshot after
zero exit, and a snapshot without the required verification log evidence.
The resume fixture checks that durable progress is unchanged and source data
is not recopied. The baseline fails the new enumeration budget.

Broader adjacent checks pass: `anchor_tip_selftest.sh` (21 cases and parser
accounting) and `cold_start_snapshot_metadata_selftest.sh` (metadata behavior
and one command per candidate). Bash syntax, architecture-tree,
shell-host-assumptions, pipefail-status-pipe, discarded-status, and
`git diff --check` pass. `make lint-fast` exceeded a 45-second bound during
initialization; no aggregate lint pass is claimed. ShellCheck and the public
node binary are absent. No compiled source changes, so compiler and live-chain
acceptance are outside this slice's validation claim.

The existing core-seal checker confirms all 554 sealed files and 80 sections
match the manifest; `git diff HEAD -- core` is empty.

Consensus and cryptographic semantics, node validation, producer flags,
snapshot verification, optional-acceleration policy, and Hetzner-owned code
are unchanged. Normal independent Zclassic validation remains authoritative.
The diff contains no keys, credentials, datadirs, generated artifacts, logs,
caches, or binaries.

Publication remains incomplete. This checkout's Git metadata is read-only:
fetch cannot write `.git/FETCH_HEAD`, and staging cannot create
`.git/index.lock`. The remote branch lookup also fails to resolve GitHub;
`origin` has no `main` ref. No commit, push, or exact remote-SHA verification
is claimed. The development branch remains unchanged. A writable Git
environment, origin connectivity, and required integration gates are needed
before publication.
