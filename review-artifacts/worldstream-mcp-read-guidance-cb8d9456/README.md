# Worldstream MCP read guidance

**Candidate** `cb8d945680161307d952d8398bdb5f55d2ce221d`  
**Parent** `370318378089a9f158ccdf4f363fd27c2a6427f2`  
**Tree** `b2d376cde075f5f92e5c1745682284c4dda8d450`  
**Changed files** `tools/mcp/mcp_serve.c`, `.claude/plugin/README.md`, `docs/agent/AGENT_API.md`, `tests/harness/src/test_mcp_serve.c`  
**Independent static review** GPT-6.1-Terra, Worldstream reviewer `/root/inventory_review`, cleared this candidate. [Review record](independent-review.txt)

## What an agent sees

Both the initialize instructions and the description returned by `tools/list` direct the agent to inspect the command's risk and authority with `z23_describe`. A read with wallet risk, core-recovery risk or owner authority is always refused. Otherwise eligible wallet-data reads require the owner to start the server with `--wallet-reads`. The shared text names the default wallet-data refusal. The plugin and agent API manual carry the same guidance. The registered tests parse and check the two emitted fields. The patch includes no enforcement or command metadata changes.

The starting main build at `109184469203b9589893e25924e376931a50f2c6` and the installed adapter both reproduced the original mismatch. During qualification preparation, upstream landed a wallet implementation change. The final patch was reapplied to that new parent. The stable patch ID was identical and both revisions received independent review. [Installed adapter trace](traces/installed/receipt.txt) · [Base refresh](candidate-base-refresh.txt)

## Measured STDIO journey

On each connection the client initialized, listed tools, found `fleet.machines`, described it, attempted it and ran `discover.search` for the same leaf. Discovery reported `effect=read`, `risk=read`, `authority=owner`. The attempted inventory returned `READ_REFUSED_OWNER_AUTHORITY`. The following search succeeded on the same connection. The candidate passed once with default settings and once with `--checkout`, `--wallet-reads` and `--fleet-writes`. There were zero retries in all four captured journeys.

| Response | Starting main bytes | Candidate default bytes | Candidate with flags bytes |
|---|---:|---:|---:|
| Initialize | 1,520 | 1,727 | 2,034 |
| List tools | 8,503 | 8,684 | 8,684 |
| Find inventory | 1,004 | 1,004 | 1,004 |
| Describe inventory | 2,292 | 2,292 | 2,292 |
| Refuse owner read | 251 | 251 | 251 |
| Run permitted search | 1,368 | 1,368 | 1,368 |

Bytes include the newline frame. The traces include all six requests, complete responses, executable SHA-256 and per-call wall times. [Starting main](traces/before/receipt.txt) · [Candidate defaults](traces/after/receipt.txt) · [Candidate with flags](traces/after-wallet/receipt.txt) · [Journey script](journey.sh)

The successful inventory CLI qualification belongs to the separate inventory repair at `4c27922080702f0c6b305e9222b5c98d8d865d0e`.

## Qualified artifacts

| Download | Bytes | SHA-256 |
|---|---:|---|
| [Native Git bundle](guidance.bundle?raw=1) | 3,070 | `c9d9417597657b680475a6b1b3dc82d31787afdfd0818997703f79ca8a2f7175` |
| [Source patch](guidance.patch) | 11,646 | `9fe0ec503dcd79898459d408ad9504249888fd4f3caded83a63542a67b37b8dd` |

The bundle requires the parent commit named above. Git verified the bundle and its single advertised candidate ref. Applying the patch to the parent reproduced the candidate tree. [Bundle verification](native.log) · [Patch verification](patch-verification.txt)

## Local qualification

- The three registered MCP groups ran cold in 4.3 seconds. `test_mcp_serve` passed 42 cases, `test_mcp_serve_apps` passed 27, and `test_mcp_plugin_call` passed one. Zero failures and zero skips. [Focused results](focused.log)
- The committed change's explicit-parent impact selection ran 31 groups cold in 134.7 seconds of runner wall time. Zero groups failed. Two checks self-skipped because host user namespaces and Linux Xvfb were unavailable. The full `agent-verify` command passed in 1,677 seconds. [Aggregate receipt](agent-verify.txt) · [Impact verdict and skips](impact-test-summary.txt)
- Fast lint passed. The differential precheck reported zero new failures across 156 gates. All eight lint preflight gates passed. [Fast lint](lint-fast.log) · [Preflight](preflight.log) · [Commands](qualification-commands.txt)
- Native offline sender precheck ran six checks and skipped the core-seal check. It reported historical land proof unavailable in this checkout. Full maintainer land proof and native acceptance remain pending. [Sender receipt](native-send.json) · [Offer manifest](guidance.bundle.offer.json)

After the final fetch the contribution was still exactly one commit outside upstream main. Upstream had advanced to `ec51c14b80c14af0f915dffe2f85977535bd17f9` without changes to any of the reviewed paths or the MCP policy. The bundle retains the exact independently reviewed parent and candidate.

This is a no-card Worldstream contribution. Kimi's bound publisher owns the native package offer and public `contrib` announcement. This review-artifact repository carries the reviewed bytes and local results.
