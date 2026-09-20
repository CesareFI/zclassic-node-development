<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bundle catalog name extraction

The cold-start-to-tip probe launched `basename` for every eligible bundle
candidate. A retained catalog of 100 bundles required 100 extra processes
before starting the measured node, even with the highest bundle first.

Replace that call with Bash directory-prefix removal. Candidates already
passed the regular-file and `.sqlite` suffix checks, so a trailing slash
cannot reach this expression. Ranking, metadata eligibility, failed markers,
tie ordering and the selected source remain unchanged. This changes benchmark
tooling only; node startup arguments, optional acceleration and independent
consensus validation are unchanged.

Measured on Linux x86_64, AMD EPYC 7402P, Bash, with an isolated warm catalog
of 100 sparse files above the existing 10 MiB floor. Each trial performs five
selections; three trials use the same fixture shape and descending heights.
The instrumented baseline calls the real `basename` and records each call.
No node, peer, production datadir or bundle content is used.

| Measurement | Before | After |
|---|---:|---:|
| Trial 1, seconds | 1.881 | 0.653 |
| Trial 2, seconds | 1.843 | 0.640 |
| Trial 3, seconds | 1.845 | 0.641 |
| `basename` commands across 15 selections | 1500 | 0 |

Median selection time decreased about 65%. This is harness setup overhead,
not a measured reduction in end-to-end IBD or the probe's reported sync time.
The remaining per-candidate height-parser subshell is outside this slice.

The new `tools/scripts/cold_start_bundle_name_selftest.sh` extracts the actual
selector, verifies unusual path bytes and exact winners, and requires zero
`basename` calls. Against the saved pre-edit source it fails that requirement;
`--baseline [probe.sh]` reports the comparison without that process assertion.
It runs through `make cold-start-snapshot-metadata-selftest`.

Validation: the new regression, the existing 14 bundle-ranking cases, the
probe's complete `--selftest`, both snapshot-metadata fixtures, Bash syntax,
and scoped lint for discarded status, pipefail status pipes, shell host
assumptions, no Python and the core seal; `git diff --check` also passed.
The Make invocation was interrupted during repository setup before its test
recipe ran; all three recipe scripts passed when invoked directly. No C
source changes require compiler validation.
The baseline source was the existing dirty checkout at HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with probe SHA-256
`1a2e401ad2c22fe8cdbb162de2a9a72c44099600dd31764e4c5e59105e3febc9`;
unrelated work is retained separately from this slice.

Publication is unavailable in this session: `.git` rejects index/FETCH_HEAD
writes as read-only, and GitHub DNS resolution fails. No commit or push is
claimed, and no remote SHA was verified. The branch remains
`agent/worldstream-ibd-20260918`.
