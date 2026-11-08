Z23 Kimi review artifacts — 2026-11-08

This is a review handoff of recoverable, frozen Z23 contributions. It is not
a release or a claim of maintainer qualification, acceptance or landing.
The artifact repository is the owner's development repository; the source
bases are commits from z23c/z23, not this repository's default branch.

Start with MANIFEST.json for full Git identities, changed files, actual saved
test commands/results, limitations, native receipt pointers, and every code
artifact's size/SHA-256. SHA256SUMS covers all publication files except itself.

Each contribution directory contains:
  change.patch       exact preserved patch, compared to its Git base..candidate
  candidate.bundle   exact original one-commit carrier, unchanged
  sources.tar.gz     complete changed source/test files from that Git commit,
                     including its generated baseline/registry files and LICENSE
  git-identity.txt   candidate Git commit, tree, and sole parent/base
  files-changed.txt  changed paths relative to that exact base

revised-s3: useful, awaiting an update/maintainer integration decision.
Its bounded copies preserve the known fixture outputs and allocation sizes.
Current upstream independently fixed zxml, while the other five banned calls
remain. Its old generated package identity must not be copied onto a new
source tree. Six focused groups, lint-fast and area preflight passed on the
frozen S3 tree. Full build/lint/suite and ASan were NOT RUN on it.

receipt-successor: useful historical correction/reference, awaiting a
maintainer decision if reused. It guards both signed multiplication bounds
and preserves the receipt checks. Focused tests, lint-fast and registered
ASan/UBSan passed on that exact candidate. Upstream separately landed the
positive-overflow saturation fix and its own receipt split. The two fixes
use different out-of-range values; do not silently substitute their policies.

cli-argv and zpd-work-start: historical split implementations whose target
work is superseded by separate upstream extractions. Exact patch IDs do not
match, and no acceptance of these original artifacts is inferred. Their
focused groups and lint-fast passed, but all full build/lint/suite attempts
failed. Both snapshots inherit the older receipt helper overflow.

historical-receipt is included only as the exact CLI bundle prerequisite.
It predates the overflow correction. The CLI carrier requires that commit;
the ZPD carrier in turn requires CLI. The corrected receipt successor is on
a separate fresh base and does not repair that old stack automatically.

All source code is unqualified for landing here. Existing local non-author
source reviews reported no blocker, but maintainer review/fetch/acceptance
remain unconfirmed. Public native post/readback IDs are identifiers of posts,
not Git commits. GitHub publication is a separate review channel.

The evidence directory contains copied saved exit values and allowlisted
verdict lines. No tests were rerun to publish this package. Private TMPDIR
paths in reproduced command descriptions are explicitly redacted; original
flags and artifact identities are retained. These are historical evidence
excerpts, not complete logs or cryptographically verifiable native posts.
Runtime logs, credentials, wallet data and management configuration are excluded.

Withdrawn S1/S2 tasks remain withdrawn. No old-scope S3 draft is offered as
the revised result. No upstream/main or main/master branch is modified.
