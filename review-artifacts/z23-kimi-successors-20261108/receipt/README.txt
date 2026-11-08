Receipt boundary successor — review handoff, 2026-11-08

Base: 7fee7ed5aabe5cfe83c526c9bd622b6e2b13f592
Candidate: 527fbe7d30741844d8aaaceca461bdf6df7c127d
Tree: fdd00eabed746e384a94c6ae7dbfa9f34f8cf4ef
Independent of S3; only tests/harness/src/test_engine.c changes.

The fixture returns unknown elapsed(-1) for invalid negative ordinals before
multiplication, keeps zero's existing arithmetic control, and retains
INT64_MAX positive overflow saturation. Ordinal itself is unchanged.
This documents a fixture convention supported by the receipt aggregator;
production validation and the general raw-duration contract are unchanged.

Direct coverage: L-1,L,L+1,U-1,U,U+1,INT64_MIN/MAX,-1,0,7, with representable
expected arithmetic. Elapsed is checked immediately after construction,
including before the capacity fixture's later assignment can overwrite it.
The RED test-only tree demonstrated all five intended negative failures;
it also had six Grok fixture failures after detached-worktree setup failed.
Final exact-candidate focused engine and lint-fast54/54 passed. Consult
MANIFEST.json and evidence/checks.txt for the actual sanitizer outcome,
instrumentation, outstanding checks and source identities.

Full build/full lint/full suite and signed landing qualification NOT RUN.
Lint's base-relative precheck was skipped because origin/main has no common
ancestor. This snapshot is unsigned; no safeguard or policy was disabled.
Non-author source review: no findings. Maintainer review pending; native
delivery, acceptance and landing unconfirmed. No self-approval or merge.

change.patch is the exact base..candidate diff. candidate.mbox includes
commit metadata; candidate.bundle carries one commit and requires the base.
sources.tar.gz contains the complete changed test file and LICENSE from
the exact Git commit. Original archived artifacts are preserved unchanged.
SHA256SUMS covers every other publication file, including the manifest.
