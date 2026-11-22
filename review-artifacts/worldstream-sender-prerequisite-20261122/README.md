# Sender offer prerequisite for multi-commit bundles

| Identity | Value |
|---|---|
| Base | `69c82a5ededecec3ca00ef734b21ae7dcb3360f5` |
| Candidate | `c9adc02457592684ddd7ddf43fc2bde5d7d37e19` |
| Reviewed tree | `d08659e1230108a8491d7d8bb53d775ca4b53927` |
| Independent review | [Exact-candidate static review](evidence/independent-review.txt) |

A clean sender can package several commits. The generated v1 offer now records the sole 40-hex prerequisite in that bundle’s Git header. This works when the tip’s parent is carried in the bundle and when upstream has advanced on a different branch. Explicit single-commit selection retains its `SEND_NOT_SINGLE` restriction.

## Artifacts

| Filename | Bytes | SHA-256 |
|---|---:|---|
| [sender-prerequisite.bundle](sender-prerequisite.bundle) | 15,046 | `7f380e3e9ed5ce63e56a8221799692741cb0ef6664bdd14b3c2a902a27e2e342` |
| [sender-prerequisite.patch](sender-prerequisite.patch) | 12,762 | `2e8ebf38d21f534579f619bb5a721d7ba602e59d59958af1a96d33cba7efc1ab` |
| [sender-prerequisite-evidence.tar.gz](sender-prerequisite-evidence.tar.gz) | 6,677 | `d7078cde84f167ad362fc2fa4b9105acc370cda0674b03b542c6310112d03f5a` |

The native contribution bundle has one head and requires the base shown above. A base-only checkout passed `dev land check_offer` with the unmodified sender sidecar, imported the exact commit and tree, and replayed the patch to that tree. [Generated offer](sender-prerequisite.bundle.offer.json) · [Packaging checks](evidence/package-check.json)

## Changed files

- tests/harness/src/test_dev_land_remote.c
- tools/command/native_dev_land_offer.c
- tools/command/native_dev_land_remote.c
- tools/command/native_dev_land_remote_shared.h

## Native round trip

| Synthetic identity | Exact Git object |
|---|---|
| Import prerequisite | `5c9591185153d277de58395641b7c5cbeb65163c` |
| Advanced origin/main | `bbf696a5fee7367276e79bc207012f23231e4a20` |
| First carried commit / tip parent | `b4405409455b4dbf6ea0f0ed085817df62ae7891` |
| Second carried commit / tip | `ed31efb61ec875162f001e730f15a96eb0948a00` |
| Expected imported tree | `9fcfe175c15e1c9e3c8a438227dc0aee364041be` |

The original sender used the first carried commit as its offer base. The receiver rejected that offer with `OFFER_BASE_MISMATCH`, exit 1. The corrected sender used the import prerequisite. The same native checker accepted the untouched offer, exit 0. Each fresh receiver contained the prerequisite and lacked both carried commits before import. Git recovered both commits and the exact expected tree. Using the carried parent in a deliberately wrong manifest still failed. [Original offer and refusal](evidence/before) · [Corrected offer and checks](evidence/after)

For a local replay, clone [the synthetic upstream bundle](evidence/synthetic-upstream.bundle) into a fresh directory, then run the installed dev binary’s `dev land check_offer` there with the absolute paths to either fixture bundle and its adjacent generated offer.

The registered sender/checker group also covers advanced origin, wrong digest and head, long header continuations, existing output paths and cleanup. A real ambiguous bundle refused offer creation and left no READY result or temporary ref. Native CLI controls separately covered zero prerequisites and a SHA-256 Git object format. Both refused with `SEND_OFFER_FAILED` and left no bundle, sidecar or READY result. [Format control](format-control.json)

## Qualification

```sh
make -s t-list
make -j4 dev-bin
make -j4 t-fast-exact ONLY=test_dev_land_remote
make -j4 lint-preflight
make -j4 agent-verify ONLY=@changed AGENT_VERIFY_BASE=69c82a5ededecec3ca00ef734b21ae7dcb3360f5
```

The focused registered group executed 1, cached 0, failed 0 and self-skipped 0. The impact run executed 45, cached 0, failed 0 and self-skipped 0. Lint preflight and the impact gate passed, including lint-fast. [Literal results and sender assertions](evidence/qualification.json)

Local Linux qualification used the admitted four-CPU, 24 GiB, zero-swap worker. Only the synthetic three-marker fixture used the packaging option `--precheck=skip`. The product bundle ran sender precheck. Skipped sender gates were `check-core-seal`; unproven sender evidence was `proof-history: land state unavailable`. The v1 contract supports one SHA-1 Git prerequisite. The bundle content digest is SHA-256. Windows runtime, remote receiver verification, R1 proof, formal acceptance and landing remain separate. No AI cohort was run for this deterministic invariant.
