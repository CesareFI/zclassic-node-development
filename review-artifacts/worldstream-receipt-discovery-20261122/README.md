# Unaided receipt-verifier discovery

Four fresh agents found the installed verifier, discovered its inputs, used it on the supplied receipt and offer, and gave the operator an appropriate next action. Each case had one session, one model turn and a 240-second limit. All four finished on the first attempt. The participant saw the same plain-language task and neutral filenames in every case. The controller kept its expected outcomes outside the participant workspace. [Frozen protocol](https://github.com/CesareFI/zclassic-node-development/tree/eb508f13e69f42fe967c1f92bb98ac20aa83d951/review-artifacts/worldstream-receipt-discovery-20261122/protocol)

The worker ran candidate `381d58c1b0e1c0b15a19aa1d0c0612d03a61d457`, executable SHA-256 `4e33a96f1966fdb7c3c7fa694702bc8d643381cd634894d034e97dc24bcee68e`. Each session used `gpt-6.1-terra` at low reasoning effort and Codex CLI 0.161.0. The non-root launcher used the existing read-only fixture profile with child network disabled, no approvals and case-local state selected before launch. The runs used synthetic receipts and public signer data. No case contained a private signing key. [Launcher configuration](protocol/launcher.json) · [Participant instructions](protocol/participant.txt)

| Trial and native result | Operator disposition | Discovery calls | Verifier calls | Elapsed (s) | Final answer (UTF-8 bytes) | Event stream (bytes) |
|---|---|---:|---:|---:|---:|---:|
| 01 · `RECEIPT_SIGNATURE_INVALID` | Withheld reliance and requested a valid signed receipt for this offer. | 9 | 1 | 26.977 | 724 | 46,845 |
| 02 · `ok` | Confirmed the receipt for this offer under established public trust. Limited the conclusion to the signed attestation. | 9 | 1 | 25.272 | 644 | 46,810 |
| 03 · `RECEIPT_SIGNER_UNKNOWN` | Left trust unresolved. Referred the signer identity to the authorized operator for independent confirmation. | 9 | 1 | 26.474 | 1,017 | 47,105 |
| 04 · `RECEIPT_VERIFIER_UNAVAILABLE` | Left validity unresolved. Referred the local state problem to the operator for diagnosis and retry. | 10 | 1 | 27.424 | 891 | 46,265 |
| **Total** | **4 completed** | **37** | **4** | **106.147** | **3,276** | **187,025** |

All four agents tried `dev help`, which returned the root menu with exit 0. They continued through installed help or registry search and read the verifier’s input contract before invoking it. There were 60 shell calls in total, zero syntax errors, zero retries after an error, and zero session restarts. The three expected verification refusals returned native exit 1. The valid receipt returned exit 0. Every call used the local CLI or shell. The byte columns measure the original answer and raw JSONL stream separately.

The before/after case snapshots matched in all four sessions, including the trust state. The traces show zero unauthorized attempts and zero completed unauthorized accesses. In trial 04 the participant echoed the diagnostic’s “owner-private signer state” wording. Its action was to refer the unavailable state to the operator. Trial 02 verified the same receipt with the public allowlist alone. [Per-call traces, participant answers and snapshot digests](trials.json)

Four cases executed, four passed, zero failed, skipped or incomplete. Each condition was observed once with this model and configuration. The optional interruption check was outside this cohort. This qualification preserves the reviewed candidate and its existing relay. [Synthetic receipt fixtures](https://github.com/CesareFI/zclassic-node-development/tree/54b2e89d9d7a7c16a96cbe14570f20b7208f211c/review-artifacts/worldstream-readback-boundary-20261122/evidence/signer) · [Existing publisher request](https://github.com/CesareFI/zclassic-node-development/issues/2#issuecomment-7079435539)
