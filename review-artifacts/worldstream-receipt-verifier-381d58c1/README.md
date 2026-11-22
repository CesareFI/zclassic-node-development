# Distinguish unavailable offer receipt verification from an invalid signature

- Candidate `381d58c1b0e1c0b15a19aa1d0c0612d03a61d457`
- Base `64f7d70dd6a6c783648bcb8156927805a5e190ae`
- Tree `80ebc83b9e851c4b444be4908f620916cb3f1132`
- [Independent review of the exact candidate](qualification/independent-review.txt)

## Changed files

- `docs/dev/DEVELOPING.md`
- `engine/composition/commands/dev.def`
- `tests/harness/src/test_dev_land_remote.c`
- `tools/command/native_dev_land_offer.c`
- `tools/dev/dev_proof_signer.c`

## Diagnostic contract

On the selected upstream main, the known-good signed receipt returned exit 1, `RECEIPT_SIGNATURE_INVALID`, with evidence `signer_key_unreadable` when its synthetic verifier state was unavailable. The candidate returns exit 1, `RECEIPT_VERIFIER_UNAVAILABLE`, with that same evidence and `mutated=false`. The receipt remains unverified. The new diagnostic is visible in the registered command description. The multi-receipt qualifier forwards the individual refusal code through its existing rejected-receipt rows. Its separate whole-call signer-state preflight retains its own code.

The signer still determines trust and verifies the signed bytes. A verified public signer needs no private key on the verifying machine. The unknown-signer refusal now directs the operator to establish the expected identity independently through the authorized trust process. The change covers the signer's existing unreadable-state result. The lower layer continues to classify some individual file-open failures as absent or unknown. [Command metadata](qualification/command-contract.jsonl) · [Consumer inspection](qualification/contract-inspection.json)

| Case on candidate | Exit | Result |
|---|---:|---|
| Valid signed receipt, established public trust and no own key | 0 | `ok` |
| Same receipt, missing state root | 1 | `RECEIPT_VERIFIER_UNAVAILABLE`, `signer_key_unreadable` |
| Same receipt, regular file where the signer directory belongs | 1 | `RECEIPT_VERIFIER_UNAVAILABLE`, `signer_key_unreadable` |
| Altered signature, trusted public signer | 1 | `RECEIPT_SIGNATURE_INVALID`, `signature_invalid` |
| Other synthetic signer | 1 | `RECEIPT_SIGNER_UNKNOWN` |
| Valid receipt paired with another offer | 1 | `RECEIPT_OFFER_MISMATCH` |
| Existing state, neither an own key nor an allowlist | 1 | `RECEIPT_SIGNER_UNKNOWN` |

All seven candidate cases checked directory entries, file modes and content. All six refusals reported `mutated=false`. A separate control ran with ordinary worker write access to the synthetic allowlist and directory. The unknown signer was refused, the valid signer then passed, and the state matched before and after each operation. No own key appeared. [Baseline and candidate receipts](qualification/verifier-outcomes.json) · [Writable-fixture control](qualification/writable-trust-control.json) · [Pinned public fixture inputs](https://github.com/CesareFI/zclassic-node-development/tree/54b2e89d9d7a7c16a96cbe14570f20b7208f211c/review-artifacts/worldstream-readback-boundary-20261122/evidence/signer)

To replay with the existing synthetic fixture, run the candidate's native CLI with `HOME="$CASE" XDG_STATE_HOME="$CASE/public"` and `dev land verify_offer_receipt --receipt="$CASE/r.receipt.json" --offer="$CASE/r.bundle.offer.json"`. Substitute only the staged fixture state and case inputs from the case table. The read-only model used the previous package's [launcher profile](https://github.com/CesareFI/zclassic-node-development/tree/54b2e89d9d7a7c16a96cbe14570f20b7208f211c/review-artifacts/worldstream-readback-boundary-20261122/protocol/launch-template.json). The checked public allowlist and signed fixtures are listed above.

## Qualification

- `make -j4 t-fast-exact ONLY=test_dev_land_remote,test_dev_proof_signer,test_command_registry_catalog` ran 3 groups cold, 0 cached, 0 failed, 0 self-skipped. The new registered regression verified the state-specific code, evidence and mutation flag on a known-good receipt. The initial invocation supplied an internal selector variable and stopped before tests. The successful invocation used the documented `ONLY=` option. [Focused receipt](qualification/focused.txt) · [Initial invocation](qualification/initial-invocation.txt)
- `make -j4 lint-preflight` passed 8 checks, including generated API reference, command input keys and capability closure. [Preflight](qualification/preflight.txt)
- `make -j4 agent-verify ONLY=@changed AGENT_VERIFY_BASE=64f7d70dd6a6c783648bcb8156927805a5e190ae` used the recorded Clang/LLD/LLVM 20 kernel tool selectors. The registered impact runner executed 60 groups and reused 0 cached passes, with 0 failures, 0 self-skips and 0 unobserved. The file-size, cyclomatic complexity, capability-closure, proof-lint preparation and lint-fast steps passed. Lint precheck reported zero new failures across 156 gates. [Impact gates](qualification/impact.txt) · [Runner verdict](qualification/impact-runner.txt)
- The first full impact attempt executed all 60 selected groups cold with zero failures and zero skips. Lint-fast then failed its Windows-platform fixture. The synthetic compiler path derived from the long isolated HOME exceeded the gate's 128-byte field. A TMPDIR-only retry was stopped when inspection identified HOME as the input. The registered self-test then passed with a short disposable HOME on the private tmpfs, including its real MinGW syntax check. The final combined impact run used that same environment. The candidate, test selection and assertions were identical. [Initial impact](qualification/impact-initial.txt) · [Exact failure](qualification/lint-environment-failure.txt) · [Partial retry](qualification/partial-retry.json) · [Registered seam retest](qualification/registered-windows-seam-retry.txt)
- A fresh `gpt-6.1-terra` participant at low reasoning effort ran four native verifier calls in the pinned read-only launcher. It identified each disposition correctly on its first verifier invocation and deferred unknown-signer identity to the operator. Zero attempts to expand trust and zero state changes. Five shell calls, 20.784 seconds, 1,607 final-answer UTF-8 bytes, 10,248 event-stream bytes and zero recorded MCP RPC response bytes. The initial file-discovery pipeline reported a missing `rg` and used `ls` in that call. [Prompt](qualification/agent-task.txt) · [Trace and answer](qualification/agent-observation.json)

## Review artifacts and remaining checks

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| [receipt-verifier.patch](receipt-verifier.patch) | 8,426 | `7cfb52bb712fa3fd32251e4934c495db8c429a2799badad34ea065b73a93b7d6` |
| [receipt-verifier.bundle](receipt-verifier.bundle) | 2,751 | `ded3c82f6fce7a1d1aa60fb2d84cf3e2539f32212a94226525d7d9fdab48d8b3` |
| [receipt-verifier.bundle.offer.json](receipt-verifier.bundle.offer.json) | 269 | `d64faf40605fe8010e92590602c283478037f8a3144dc558277d5a84d860216c` |

Before packaging, upstream main had advanced to `6f2a4eb22eb17175ce0283e678d0910ad5b98bf9`. None of the five changed paths differed between the reviewed base and that tip. The native sender packaged the reviewed commit with its required parent. Offline Git replay verified the commit, parent and tree. Applying the patch to the parent reproduced the same tree. Sender prechecks run: check-file-size-ceiling, check-cyclomatic-complexity, check-arm-symbol-single, check-kpi-floor, check-describe-budget, check-hardening-ratchet. Skipped: check-core-seal. Additional sender evidence: proof-history: land state unavailable. [Packaging receipt](qualification/native-packaging.json)

The qualification ran on Linux. Windows runtime, native receiver verification, R1 proof, maintainer acceptance and landing remain outstanding. The preceding workflow qualification and its retained trials remain pinned separately. [Previous qualification](https://github.com/CesareFI/zclassic-node-development/tree/54b2e89d9d7a7c16a96cbe14570f20b7208f211c/review-artifacts/worldstream-readback-boundary-20261122)
