# Worldstream allowlist-open correction

| Identity | Value |
|---|---|
| Reviewed candidate | `a2302436f42f2e68810efc125c4b35cf1c4dd211` |
| Tested parent | `82df97517f00e260710415117a2163c58ef289ca` |
| Reviewed tree | `7b3dbd5ee3c4e0a12895e832ca18e3b66667f873` |
| Git import prerequisite | `2a93470e27c2197ff13813e3a6f6f46893c5a538` |
| Independent review | [Exact-candidate review](evidence/independent-review.txt) |

An existing allowlist that the worker cannot open now yields `RECEIPT_VERIFIER_UNAVAILABLE` on a required lookup. A missing allowlist continues to yield `RECEIPT_SIGNER_UNKNOWN` for the foreign signer. The fix changes `tools/dev/dev_proof_signer.c`, its header `tools/dev/dev_proof_signer.h`, and `tests/harness/src/test_dev_proof_signer.c`. [Patch](allowlist-open.patch)

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| [Native Git bundle](allowlist-open.bundle) | 8,085 | `831c5dc0ac977633fc0d6cec24ca900b7ae5f388156321724414d663be445a66` |
| [Original qualification archive](trust-file-diagnostic.tar.gz) | 6,860 | `fa98d19f5321b1f4ae74a34ab15f3ada777dcc79fc6cc01e414772a805ad652a` |

## Import the qualified tree

The bundle contains two commits. Its first commit is the tested parent, an exact local replay of `381d58c1b0e1c0b15a19aa1d0c0612d03a61d457` on `2a93470e27c2197ff13813e3a6f6f46893c5a538`. Both versions of the diagnostic change have stable patch ID `56a4933683377361cdf98af34f9d61491388e96d`. Its second commit is the allowlist correction. The only Git object history the recipient must obtain separately is the public upstream prerequisite. The original relay has its own [native announcement and readback](https://github.com/CesareFI/zclassic-node-development/issues/2#issuecomment-7082048166).

From the downloaded package directory, start with a fresh repository. These commands import the existing objects. The pinned qualification applies to the listed candidate, parent and tree.

```sh
sha256sum -c SHA256SUMS
pkg=$(pwd -P)
git init --quiet import
git -C import fetch --depth=1 --no-tags https://github.com/z23c/z23.git 2a93470e27c2197ff13813e3a6f6f46893c5a538
git -C import checkout --quiet --detach FETCH_HEAD
git -C import bundle verify "$pkg/allowlist-open.bundle"
git -C import fetch --no-tags "$pkg/allowlist-open.bundle" HEAD:refs/heads/qualified
git -C import rev-parse qualified qualified^ qualified^^ 'qualified^{tree}'
```

A fresh checkout with the upstream commit first passed native `dev land check_offer` using the [verified offer](allowlist-open.bundle.offer.json). Git imported the previously absent replay parent and candidate and returned the four expected identities. The connectivity check passed. [Import and native check receipts](packaging/verification.json)

The native sender's clean-HEAD mode wrote the bundle. Its original offer used the tested parent as `base`. That offer returned `OFFER_BASE_MISMATCH` because this two-commit bundle begins at the upstream prerequisite. The delivered offer changes only that field to the actual prerequisite. The sender's bundle bytes are original. [Original sender offer](packaging/sender-original-offer.json)

## Retained qualification

The non-root worker verified the known-good receipt before and after restoring the public allowlist. Mode `000` produced `EACCES`. The candidate returned `RECEIPT_VERIFIER_UNAVAILABLE`, evidence `signer_key_unreadable`, exit 1 and `mutated=false`. Genuine absence produced `ENOENT`, `RECEIPT_SIGNER_UNKNOWN` and exit 1. All eight before/after case snapshots matched. Both binaries passed the 65,536-byte and 65,537-byte boundary controls. [Native controls](evidence/native-controls.json) · [Size controls](evidence/size-controls.json)

Both focused registered groups passed cold. `lint-preflight` and `agent-verify` passed. The impact run executed 56 groups with zero cached, failed or self-skipped. The final `lint-fast` gate passed. Literal commands and original result lines are retained in the package. [Qualification receipt](evidence/qualification.json)

Linux qualification and independent static review cover allowlist open failures. Later read, size and allocation handling and individual seed-open behavior retain their prior semantics. Windows runtime was not exercised. Sender precheck ran six gates, skipped `check-core-seal`, and lacked the land state's canonical proof history. Native relay, receiver-side verification, R1 proof, acceptance and landing each require their own evidence.
