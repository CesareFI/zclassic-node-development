<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream replay supply observation cost

The replay canary's legacy unquoted `total_amount` fallback starts `grep`,
`head`, and `sed` for each observation. Replace that pipeline with a Bash
regex, preserving the first line-local digit/dot token, exact decimal text,
quoted-value precedence, output newlines, and success status on a miss.
This is an existing field extractor, not a general JSON validator.

This slice owns only the `json_amount` hunk in
`tools/scripts/replay_canary.sh`, the new
`tools/scripts/replay_canary_amount_selftest.sh`, and this report.
Pre-existing integer/string reader work and unrelated staged/unstaged edits
are preserved. The branch remains `agent/worldstream-ibd-20260918` at
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

Measured on Linux x86_64, Bash 5.2.21, with uncontrolled host load and warm
host caches. Each trial performs 300 captured reads of the same unquoted
eight-decimal supply response. Fixtures start no node and access no network,
wallet, peer, or production datadir.

| Measurement | Before | After |
|---|---:|---:|
| External parsers per unquoted amount | 3 | 0 |
| Trial 1 wall seconds | 1.942 | 0.857 |
| Trial 2 wall seconds | 1.920 | 0.852 |
| Trial 3 wall seconds | 1.925 | 0.838 |
| Median wall seconds | 1.925 | 0.852 |

The median helper time decreases about 56%. The quoted-field probe and
command-substitution subshells remain. These supply reads occur during final
canary evaluation; this does not establish faster chain validation or
end-to-end IBD. Heavy audit RPC cost is not measured by this fixture.

Reproduce the baseline helper while retaining the current string reader:

```bash
{
    sed -n '/^json_str() {/,/^}/p' tools/scripts/replay_canary.sh
    git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/scripts/replay_canary.sh |
        sed -n '/^json_amount() {/,/^}/p'
} > /tmp/worldstream-replay-amount-baseline.sh
bash tools/scripts/replay_canary_amount_selftest.sh --bench /tmp/worldstream-replay-amount-baseline.sh
bash tools/scripts/replay_canary_amount_selftest.sh --bench
```

Both implementations pass 29 exact-byte/status cases, including quoted and
unquoted values, precision beyond machine integers, missing fields, duplicate
fields, all line-local whitespace, newline boundaries, preserved numeric-prefix
behavior, and a 256 KiB response. The baseline intentionally fails the final
zero-external-parser gate. Timing is informational; parser invocation count is
the deterministic regression. The new helper also works with no executables
on PATH.

The existing `replay_canary_parser_selftest.sh` passes 23 integer-reader
cases and all 13 verdict scenarios, including supply mismatch, rejection,
checkpoint mismatch, skipped verification, failed validation, and timeout.
The existing `replay_canary_string_selftest.sh` passes 26 cases. Bash syntax,
shell-host assumptions, pipefail-status-pipe, discarded-status, no-Python,
no-API-key, architecture, consensus-parity, and `git diff --check` pass.
All 554 sealed files and 80 section seals match. No consensus predicate, acceptance threshold,
optional-acceleration policy, or Hetzner-owned runtime surface changes.
The new diff contains source, test code, and this report only; temporary
measurements and baseline copies stay outside the repository under `/tmp`.

Publication remains incomplete. Fetch cannot write `.git/FETCH_HEAD`, and
`origin/main` is absent locally. `git ls-remote origin` fails to resolve
GitHub. The canonical `make -j2 t-fast ONLY=replay_canary_verdict` reaches
its 45-second execution bound after Tor setup fails to write `.git/config`;
`make -j2 lint-fast` also reaches its 45-second bound without a final verdict.
Neither is a pass. The pre-existing index remains byte-for-byte unchanged;
no commit, push, or remote-SHA verification is claimed.

The whole driver SHA-256 before this slice was
`9c8d105db0c48c564e0905417cb23bfe725a6069e34df098270083a26b8f1da7`;
afterward it is
`16858273c4642b3b75f601a70031c69ba1a12c4240ef6faa453f9913e545f2df`.
These identify working-tree bytes including prior work, not a published commit.
