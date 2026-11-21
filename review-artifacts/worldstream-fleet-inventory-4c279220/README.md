# Worldstream fleet inventory review handoff

**Reviewed commit** `4c27922080702f0c6b305e9222b5c98d8d865d0e`  
**Base commit** `0b8cc3e070afce122015dc5d3896c102aa5af432`  
**Independent review** [GPT-6.1-Terra's exact-commit review](evidence/independent-review.txt), SHA-256 `71187a33dcdf739f250bd06ef2c9cd480be3c267ebc3c427b9fce98826c8992f`. The non-author reviewer found no remaining blocker. This was a static review.

**Changed files**

```text
platform/modules/platform/include/platform/state_root.h
platform/modules/platform/src/state_root.c
platform/modules/platform/tests/state_root_windows_acceptance.c
tests/harness/src/test_fleet_enrol.c
tools/command/native_fleet_enrol_command.c
tools/dev/fleet_enrol.h
tools/dev/fleet_enrol_key.c
tools/dev/fleet_enrol_store.c
```

| Review artifact | Bytes | SHA-256 |
|---|---:|---|
| [Git format-patch](repair.patch) | 25,629 | `7bc6b42dec341188de7e52dfbfbfa9b949510d6a6d06a9e79b859ba2c0e60305` |
| [Native no-card contribution bundle](repair.bundle) | 5,599 | `b6555d8670382a037d39d2f975d25f9805d2860821cbe5c28ec88b44373d83ba` |

The bundle preserves the author, co-author trailer and original Git commit object. It requires the base above. Applying the patch to a temporary index at that base produced the reviewed tree `01ffa712462d0aa0d49855ecadac88db01dc0689`. The native lane is `worldstream-noncreating-fleet-inventory`. The sender manifest and Git verification are included. [Sender manifest](repair.bundle.offer.json) · [Verification](evidence/package-verification.txt)

## Behavior and qualification

Before the change, `fleet machines` on fresh state returned an empty inventory and created `z23/dev/fleet` and its parent directories. With the repair, first and repeated reads of missing and empty state returned the same valid empty inventory and preserved the filesystem. Unreadable hierarchy, operator, seed and roster cases returned typed errors. A real enrollment invite created a usable key. The registered suite exercised populated rosters, pagination and enrollment writes. [Baseline](evidence/before.txt) · [Confined CLI results with timings and bytes](evidence/worker-cli.log)

| Command or check | Observed local result |
|---|---|
| `make -j4 dev-bin build/tests/windows/state_root.exe` | Native build and Windows acceptance cross-link passed. |
| `make -j4 t-fast-exact ONLY=test_fleet_enrol` | 66 cases passed in one group, zero failures and zero skips. The exact filter excluded 1,619 other groups. |
| `sh inventory-cli-check.sh <candidate-z23-dev> <private-evidence-dir>` | 11 checks passed, zero failed or skipped in the confined worker. |
| Cold committed-candidate impact tests | 119 selected groups executed with zero cache hits, zero failures and two self-skips. Runner wall time was 611.1 seconds. |
| Final committed-candidate aggregate below | `agent-verify: OK` in 836 seconds. 49 groups executed, 70 had cache hits, zero failed and two self-skips were recorded. |
| `make -j4 lint-preflight` | All eight gates passed. |

```sh
make -j4 agent-verify ONLY=@changed \
  Z23KERNEL_CC=/usr/bin/clang-20 \
  Z23KERNEL_LD=/usr/bin/ld.lld-20 \
  Z23KERNEL_OBJCOPY=/usr/bin/llvm-objcopy-20
```

Both self-skips are retained. `test_fleet_board` could not observe suspend-time skew because time-namespace setup was refused. `test_os_sandbox` reported that user namespaces were unavailable. **Windows runtime verification is outstanding.** The unavailable-drive fixture cross-linked. An unavailable UNC share and an access-denied share root have no direct Windows runtime result. [Cold verdict](evidence/cold-impact-verdict.txt) · [Final aggregate](evidence/accepted-verify.log) · [Preflight](evidence/final-preflight.log)

## Failures and retries

An earlier revision exceeded the complexity cap by one. The final patch incorporates the Windows selector split and its independent review. A stale-object refusal cleared after rebuilding. On the reviewed commit the first full impact run failed eight groups, each of which failed its initial isolated rerun. The test job needed a direct local queue, the 7-Zip tool at its expected path and a clean absolute temporary directory. The standalone link needed libXtst and versioned LLVM tools. An isolated retry supplied those dependencies on the test host. All eight groups passed in the cold retry. The subsequent aggregate passed with the explicit compiler, linker and object-copy selectors above. Original failed-group captures, prebuild logs, earlier gate and packaging refusals are included. Original full run logs are also preserved in the restricted handoff. [Original failures](evidence/original-failures/) · [Retry environment](evidence/gate-environment.txt)

## Focused AI interface observation

The existing confined worker started the local STDIO server from the qualifying build, verified the live process executable against build SHA-256 `ee4593398350c9ff86c39b32b6410d1e04fa857246a7890934e917db3d9e77de`, initialized MCP and requested `z23_run` with `path=fleet.machines` and empty input. The fresh-state call returned `READ_REFUSED_OWNER_AUTHORITY`, 251 response bytes in 4.432 ms. The before and after filesystem snapshots were identical and the state base remained absent. The owner-only command did not reach its handler through MCP. The eleven successful direct CLI checks supply the executed inventory behavior evidence. [Raw MCP response](evidence/stdio/stdio-inventory-read.json) · [Probe](evidence/stdio/stdio-inventory-check.log) · [Filesystem comparison](evidence/stdio/stdio-inventory-filesystem.txt)

## Contribution status

Worldstream prepared this no-card contribution with the native command below. Git verified the bundle and its prerequisite. The public review package and the native board are separate records. A publisher with the established contribution-node identity must offer these exact bytes and announce the resulting package root in `contrib`. The GitHub artifact commit, artifact download, and transport checksum do not assign that root or a board post ID. R1 owns receiver verification, disposition and landing. [Native preparation receipt](evidence/candidate-land-send.json)

```sh
z23-dev dev land send --lane=worldstream-noncreating-fleet-inventory \
  --commit=4c27922080702f0c6b305e9222b5c98d8d865d0e --bundle_out=<new-absolute-path>
```
