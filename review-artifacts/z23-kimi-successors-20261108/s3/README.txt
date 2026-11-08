S3 successor — review handoff, 2026-11-08

Base: e73d3ec9c4e4b842afa9eae9f78d2de7408bf389
Candidate: c14011ede09dd22b1b5561ed03b207f30cc55f94
Tree: c2b1029681caa9a6d52af8f84a731fb7562aaf9a
Independent of the forthcoming receipt candidate. CLI/ZPD remain historical.

Only the remaining five string calls across four C files are replaced.
Exact contents, NULs, spacing, ordering and random inputs are preserved;
bounded-format results are checked so truncation cannot silently pass.
The upstream zxml fix is untouched. Supported generators refreshed one
package declaration, no dependency pins, and retired four hardening rows.

Five of six focused groups passed initially (commons 80/80); the TCP group
failed fixture initialization under the sandbox. Only that group was rerun
with authorized execution and passed all26 sub-suites. The original FAIL
is preserved. Final lint-fast54/54, lint-preflight6/6, metadata/hardening PASS.
Full build/full lint/full suite and sanitizers NOT RUN on this successor.
Lint's base-relative precheck was skipped: origin/main has no merge-base.
The exact snapshot is unsigned; no hook or signing policy was weakened.

Non-author source review: no findings. Maintainer review remains pending;
native delivery, acceptance and landing are unconfirmed. See MANIFEST.json
and evidence/checks.txt for exact commands, identities, failures and limits.

change.patch is the exact base..candidate diff; candidate.mbox includes
commit metadata; candidate.bundle carries one commit and requires the base.
sources.tar.gz contains complete changed source/tests/generated files and
LICENSE from the candidate Git object. Original archived artifacts unchanged.
SHA256SUMS includes the manifest and every other file except itself.
