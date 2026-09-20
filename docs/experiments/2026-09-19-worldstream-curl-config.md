<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: isolate benchmark HTTP observers from default curl config

Branch: `agent/worldstream-ibd-20260918`. Clean comparison base:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fresh-sync benchmark inherited the operator's default `.curlrc` for its
RPC, explorer-readiness and explorer-size probes. A configured retry delay
adds time to failed observations; `--max-time` limits each transfer, not the
whole retry sequence. Configured output redirects or extra URLs can also
remove or contaminate evidence. This is benchmark observer overhead and
reproducibility work, not a change to node synchronization.

All three probes now put `-q` first in curl's arguments, disabling the default
configuration file. Explicit command options remain authoritative. Environment
variables are not cleared. The new regression is a prerequisite of
`make bench_fresh_sync` and can run directly without a node build:

```sh
bash tools/scripts/bench_fresh_sync_curl_config_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_curl_config_selftest.sh --bench
```

## Reproduction and measurements

Linux x86_64, GCC 14.2.0, curl 8.5.0, warm ordinary filesystem caches,
uncontrolled ambient host load. The harness extracts the actual four HTTP
helpers, compiles them as C23, and preserves their curl arguments and order.
A wrapper substitutes fixed loopback URLs with local `file://` fixtures;
the installed curl performs the transfers. No node, sockets, peers, chain
data, real credentials or production datadir participates.

With `retry = 1`, `retry-all-errors` and `retry-delay = 1` in a temporary
`.curlrc`, each measurement invokes the three observers against missing files.
Each triple must still report all observations unavailable. Baseline runs
precede candidate runs, with three repetitions per version:

| Source | Baseline seconds | Candidate seconds |
|---|---|---|
| Clean committed base, only this fix applied | 3.051890 / 3.050380 / 3.050580 | 0.042739 / 0.044994 / 0.041796 |
| Existing dirty working source, only this fix added | 3.049503 / 3.048167 / 3.047587 | 0.040457 / 0.039850 / 0.039481 |

The clean median falls from 3.051 seconds to 0.043 seconds by removing
inherited retries. This is an adversarial configuration fixture, not a claim
about default-case speed or end-to-end IBD/time-to-tip.

The default regression exercises successful observations with an empty config,
then configured redirects and extra URLs, then failed transfers with an extra
configured body that contains the readiness marker. The baseline fails on the
redirect case. Removing `-q` separately from each observer is detected.

## Validation and remaining work

The new regression passes against both the clean candidate and the dirty
working source with `-std=c23 -Wall -Wextra -Werror` and GCC `-fanalyzer`.
The existing command-reader, HTTP-deadline and page-size regressions also
pass with static analysis in the working checkout. Their earlier source
changes remain separate from this slice. Standalone driver compilation passes;
existing unchecked `system` results and copy-command truncation warnings remain
outside the edited helpers. Bash syntax and `git diff --check` pass.

Architecture-tree, shell-host-assumption, pipefail-status and discarded-status
checks pass. A bounded `make lint` attempt in the clean checkout did not finish
within 60 seconds; it was still building prerequisites. No full lint, native
node acceptance, macOS execution or live-chain timing pass is claimed.

Only the benchmark's curl options, Makefile test registration, regression and
this record belong to the slice. Consensus, validation, optional acceleration
policy and Hetzner-owned scheduling, database and runtime code are untouched.
The slice includes no secrets, logs, caches, binaries or generated outputs.

The original checkout's Git metadata is read-only. A separate local checkout
at `/tmp/worldstream-curl-config/checkout` holds the clean slice on the same
development branch; no earlier dirty work is included. GitHub DNS resolution
failed for fetch and remote lookup. Publication and exact remote-SHA
verification remain incomplete, and the full publication gates still need to
pass before pushing. Temporary fixtures and logs remain outside the commit.
