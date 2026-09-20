<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream replay string observation cost

The replay canary starts `grep`, `head`, and `sed` for every string field
read during progress polling and final observation. Replace that pipeline
with a Bash regex for the same first line-local quoted field. This changes
only benchmark observation, not node behavior, validation, verdict predicates,
or acceptance thresholds. Escapes remain text; this is not a JSON decoder.

This continuation owns only the `json_str` hunk in
`tools/scripts/replay_canary.sh`, the standalone
`tools/scripts/replay_canary_string_selftest.sh`, and this report. The
pre-existing staged integer-reader change and all other dirty work are
preserved. The branch remains `agent/worldstream-ibd-20260918`, based on
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

Measured on Linux x86_64, GNU Bash 5.2.21, with uncontrolled host load.
Each trial performs 900 reads through command substitution, matching the
caller's process pattern. Inputs are fixed state, hash, and quoted amount
fields; no node, peer, wallet, or production datadir is opened.

| Measurement | Before | After |
|---|---:|---:|
| External parsers per string | 3 | 0 |
| Trial 1 wall seconds | 4.651 | 1.173 |
| Trial 2 wall seconds | 4.622 | 1.172 |
| Trial 3 wall seconds | 4.631 | 1.162 |
| Median wall seconds | 4.631 | 1.172 |

The median observer time falls about 75%. Command-substitution subshells
remain. This does not establish a reduction in chain-validation time or
end-to-end IBD time. The unquoted amount fallback still starts external
parsers; its importance relative to RPC latency remains unmeasured.

Reproduce the baseline and new reader with:

```bash
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/replay_canary.sh > /tmp/worldstream-replay-string-baseline.sh
bash tools/scripts/replay_canary_string_selftest.sh --bench /tmp/worldstream-replay-string-baseline.sh
bash tools/scripts/replay_canary_string_selftest.sh --bench
```

The baseline intentionally fails the final no-external-parser cost gate.
Both readers pass all 26 output/status compatibility cases, including absent
and non-string fields, duplicate fields, line boundaries, escapes, quoted
amounts, and a 256 KiB reply. Timing is informational; the process-cost gate
is deterministic. The measured baseline file included the existing integer
optimization, which does not participate in this string-only fixture.
Its SHA-256 was
`66cc6dc06d21c5a58869da9ebcd759412a81c1e8e08b1e5d741ece53a9a1338e`;
the updated driver is
`9c8d105db0c48c564e0905417cb23bfe725a6069e34df098270083a26b8f1da7`.

Broader fixture validation through the existing
`replay_canary_parser_selftest.sh` passes 23 integer-reader cases and 13
verdict scenarios, including rejects, checkpoint and cross-node mismatches,
skipped verification, failed validation, and timeout. Bash syntax,
shell-host assumptions, pipefail-status-pipe, discarded-status, no-Python,
no-API-key, no-warning-suppression, architecture, consensus-parity checks,
and `git diff --check` pass. All 554 sealed files and 80 section seals
match. No consensus, custody, optional-acceleration policy, or Hetzner-owned
runtime surface changes. The exact new diff contains source, regression
code, and this report, with no secrets or benchmark output artifacts.

Publication is incomplete. `make -j2 t-fast ONLY=replay_canary_verdict`
cannot register the Tor submodule because `.git/config` is read-only and
reaches the 120-second execution bound. `make -j2 lint` also reaches its
120-second bound without producing gate results. Neither is a pass.
Fetching the named
development branch cannot write `.git/FETCH_HEAD`, and `git ls-remote origin`
cannot resolve GitHub. The origin also has no `main` ref. No commit, push,
or remote-SHA verification is claimed; the pre-existing index is preserved.
Focused fixture and lint results do not replace complete publication gates.
