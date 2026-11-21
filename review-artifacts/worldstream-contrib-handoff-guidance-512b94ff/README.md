# Worldstream contribution handoff guidance

**Reviewed commit** `512b94ff0c1b27c5586f55565f8e7a08b9e0fa1e`  
**Parent** `4c1487a1034ed0c88fcbe800c0d8fce4d1678b71`  
**Tree** `a03faf573afd9b0b1d6dc54546d378dd986a4083`  
**Files** `tools/command/native_dev_land_remote.c` and `tests/harness/src/test_dev_land_remote.c`  
**Independent review** GPT-6.1-Terra cleared the exact commit after tracing path validation through the sender. [Review record](independent-review.txt)

## Choosing a route

The previous sender's offline reply gave a volunteer only the fleet room and queue host. Both the public and internal manuals prescribe the same packaging command. The changed `next_action` presents the two audiences explicitly. [Original output](wire/before/next-action.txt) · [Candidate output](wire/normal/next-action.txt)

| Intended audience | What the sender tells the caller |
|---|---|
| Public contributor | Offer on an authorized package-hosting node. Post a `need` in public room `contrib` with card ID or `no card`, commit, offer root, SHA-256, size, serving onion if available, and the literal acceptance command and result line labelled local. |
| Existing fleet and queue | For board intake, offer and post `READY` with SHA-256, root and size in room `fleet`. For direct delivery, transfer the bundle to the authorized queue host and run `z23-dev dev land receive` there with its path and lane. |

Both alternatives come from the same formatter. A long output path invokes the compact form, which directs the caller to substitute the full `data.bundle` value. Neither form chooses an audience based on the presence of a host, `--bundle_out`, or lane naming. [Compact output](wire/compact/next-action.txt) · [Output size bound](format-bound.txt)

## Offline sender evidence

All captures used the same synthetic commit and lane, a local bare Git origin and a path containing a space. The starting-main binary and the installed binary both reproduced the ambiguity. The candidate's ordinary and compact responses carried the expected fields. The Git bundle, offer manifest, SHA-256 and `data.ready` matched the starting-main fixture. The fixture used the documented precheck skip for its synthetic repository. The actual contribution bundle used the default sender precheck. [Comparison](offline-comparison.txt) · [Baseline check](baseline.txt)

| Sender | Path bytes | Full reply bytes | Elapsed | Attempts |
|---|---:|---:|---:|---:|
| Starting main | 89 | 1,337 | 85.047 ms | 1 |
| Candidate, ordinary | 89 | 1,715 | 95.530 ms | 1 |
| Candidate, compact | 1,272 | 4,022 | 86.944 ms | 1 |

The full reply includes the bundle and manifest paths outside `next_action`, so the compact case still has the larger overall reply. No live offers, board announcements, or queue receives were used in these checks.

## First-time agent exercise

A fresh GPT-6.1-Terra participant received one scenario at a time, the corresponding emitted output, and the standard documentation excerpts. It had no prior thread context or feedback between scenarios. Scoring criteria were recorded beforehand. Elapsed times are measured from the scenario message to the final answer in the participant's event log. [Scoring](journey/result.txt) · [Timestamps, calls, retries and bytes](journey/measured.tsv)

| Scenario | First answer | File reads | Retries | Elapsed | Answer bytes |
|---|---|---:|---:|---:|---:|
| Public, ordinary output | Correct public `need` and all required fields | 1 | 0 | 8.341 s | 808 |
| Internal, compact output | Correct fleet `READY` fields and direct receive alternative | 1 | 0 | 9.307 s | 913 |

The packets, exact answers and calls are in `journey/`. Offers and results mentioned in the scenarios were illustrative. The participant only read the packets.

## Reviewed transport

The native sender packaged commit `512b94ff0c1b27c5586f55565f8e7a08b9e0fa1e` using its default precheck. Git verified the single sender ref and required parent `4c1487a1034ed0c88fcbe800c0d8fce4d1678b71`. The patch applied to that parent recreates tree `a03faf573afd9b0b1d6dc54546d378dd986a4083`. At packaging, the fetched upstream head was `476f066ed6959b19ee347d8308db4d8eb3596a44`. The candidate still contributes one commit and the intervening upstream commits touched neither reviewed file. [Native receipt](native/native-send.json) · [Git verification](native/native.log) · [Tree verification](patch-verification.txt)

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| [Native Git bundle](native/guidance.bundle) | 14,355 | `e346583525a3c1c85508e41ca895b1df9582dca2fc56522981053ec3ba823b73` |
| [Git format patch](guidance.patch) | 8,248 | `ba10e22014080d72eb8e73a57ba8c35cfdb3b7dab2d26cbbe2b380f8f9204cf8` |

The sender ran six local prechecks. Its receipt lists `check-core-seal` as skipped and reports proof history unproven because the canonical land worktree was unavailable. The adjacent offer JSON is the sender's local manifest. Package hosting, either board route, receiver acceptance, and landing are distinct later operations.

## Qualification history

The registered sender group ran cold with 83 passing cases, zero failures and zero skips. Preflight lint passed all eight registered checks. [Sender log](focused.log) · [Lint log](qualification/preflight.log)

The first impact run selected and executed all 45 groups. Forty-three passed, and the two remote-proof groups failed at runner admission. The first retry forwarded the scheduler-supplied marker through the clean environment and reached the next requirement, a writable ancestor with the cgroup v2 memory controller delegated to the test account. [First impact receipt](qualification/first-impact/agent-verify.rc) · [Placement failure](qualification/first-impact/placement.log) · [Command failure](qualification/first-impact/command.log) · [Marker-only retry](qualification/retry-remote.log)

The controller then used a transient, memory-delegated test service under the same development slice while the shared devbuild scheduler held the project slot. The service had a 24 GiB memory cap, zero swap, a four-core quota and CPUs 2–5. The work ran as z23dev inside a kernel-delegated child cgroup with a private /tmp and read-only fixture tools. Its receipt records actual cgroup memory peak and CPU usage. A launcher check exposed a working-directory error before make could run any tests. The corrected launcher set the reviewed checkout explicitly. Both remote-proof groups then passed cold, with zero skips, in 36.7 seconds. [Runtime check](qualification/bounded-workload-check.txt) · [Working-directory error](qualification/probe-working-directory.log) · [Two-group retry](qualification/proof-pair.log)

The final explicit-base `agent-verify ONLY=@changed` passed in 427 seconds. The selector chose 45 groups. The registered runner executed 26 and reused 19 cached passes, with zero failures, self-skips or unobserved results. Capability closure, proof-lint prebuild, lint-fast and both structural checks passed. The source and assertions were identical across attempts. [Final gate receipt](qualification/final-agent-verify.rc) · [Selection and runner receipt](qualification/impact-test-receipt.txt) · [Resource and exit receipt](qualification/final-impact.log)

An offline Git unpack into a temporary bare repository also verified the pack and matched the reviewed commit, parent, tree and both changed paths. [Unpack receipt](native/bundle-replay.log)

**Disposition** Local qualification and independent review are complete. This is a separate, prepared contribution. No live offer, board announcement, queue delivery or landing was performed. The preceding Worldstream contributions retain their own artifacts and publisher requests.
