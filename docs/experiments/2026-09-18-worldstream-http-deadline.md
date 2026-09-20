<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream cold-start HTTP observation deadlines

The standalone cold-start benchmark checked its 1,800-second deadline only
between polls. Its RPC and explorer curl commands had no transfer deadline,
so a connected endpoint that stopped responding could prevent the next check
indefinitely. This is a benchmark observation bottleneck, not a measured
chain-processing bottleneck.

All three HTTP command constructors now specify a two-second transfer limit.
Explorer pipelines also propagate curl failure through Bash `pipefail` to the
existing command reader. Otherwise a partial page containing `Latest Blocks`
could count as readiness despite timing out, and its byte prefix could be
reported as a complete page. Successful observations retain their values.
The two-second limit matches the existing polling interval; slow responses
become missing observations. This is a per-request limit, not a strict deadline
for the entire benchmark. Sequential requests and final diagnostics can still
extend the outer budget. Explorer probes now require Bash as well as curl.

Baseline: `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, with the pre-existing uncommitted
Worldstream work preserved. Before this slice, `tools/bench_fresh_sync.c` had
SHA-256 `2ee846dfb2e315e1f65d83ec36e9bba11ffcd8fb1a5fe1f382db1bbf057b3e95`;
afterward it has
`e26f236faf2d3afba4240850e83cf6f7f53b92ebbfe4a7630fb73e829c1118a7`.
The slice owns only the HTTP command/comment changes, the new
`tools/scripts/bench_fresh_sync_deadline_selftest.sh`, its invocation in the
existing Makefile selftest target, and this note. It relies on the existing
pending command-reader change that rejects unsuccessful and truncated output.

The regression compiles the actual observation helpers and substitutes a
controlled curl executable. It models a six-second stalled transfer, honors
the supplied transfer limit, and returns curl's timeout status with optional
partial output. On Linux x86_64 / AMD EPYC 7402P / GCC 14.2, the baseline
failed the deadline assertion after 6.004 seconds. Updated silent and partial
RPC, explorer-readiness and page-size observations returned in 2.003–2.008
seconds, rejecting every incomplete response. Healthy responses still pass.
Removing `pipefail` makes the partial-page readiness test fail. Wall times are
single fixture observations under uncontrolled host load.

Reproduce with:

```bash
bash tools/scripts/bench_fresh_sync_deadline_selftest.sh --analyze
```

An optional source path selects a saved baseline. Loopback socket creation
was refused by this sandbox, so this evidence tests the harness's command and
observation contract, not real libcurl network timeout timing. It establishes
no end-to-end IBD or time-to-tip speedup.

The new regression and both existing fresh-sync regressions pass directly.
Extracted production helpers pass C23 `-Wall -Wextra -Werror` and GCC
`-fanalyzer`. The complete benchmark builds with its target's compiler flags;
a stricter `-Werror` build fails on the same seven baseline warnings (ignored
`system` results and copy-command truncation). No warning policy was changed.
The Make selftest invocation was interrupted during repository setup without
reaching its recipe; `make lint-fast` likewise exceeded a 50-second bound.
Neither aggregate is claimed green.

Shell syntax, whitespace, architecture, shell-host assumptions,
discarded-status, pipefail-status, no-API-keys and no-Python checks pass.
All 554 sealed core files and 80 section seals verify, and the exported root
mirror matches. Consensus and independent validation are unchanged; optional
acceleration remains optional. No Hetzner-owned scheduling, database or runtime
surface changed. The existing Git index was preserved byte-for-byte as a
diff. No secrets, binaries, logs or temporary benchmark outputs are part of
this slice.

Publication is blocked: Git metadata is read-only, `origin/main` is absent
locally, and the origin query fails on GitHub DNS. No commit, push or remote-SHA
equality is claimed. Integration and publication gates remain outstanding.
