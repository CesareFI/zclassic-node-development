<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: isolated readiness observer process cost

Scope: startup/resume benchmark observation in
`tools/scripts/isolated_node_env.sh`. No node runtime, consensus, scheduling,
database, validation, or acceleration policy changes.

Baseline: `c1f7863d098e1efaa8deba240c580ae0559312a5`; the two changed shell
files were clean at entry. Other staged and unstaged work was left separate.
Each successful `iso_rpc_nonnegative_result` sample used two `printf | jsonq`
pipelines. Supplying the already captured response through Bash here-strings
removes both producer processes. Both full-document typed JSON checks remain:
an explicit null error and a nonnegative integer result are required.

Measured on Linux x86_64, AMD EPYC 7402P, Bash 5.2.21, GCC 14.2.0. The real
in-tree C23 `jsonq` was compiled with `-O2 -Wall -Wextra -Werror -pedantic`.
The RPC fixture always returns height 3196929, null error, and id 1. Runs
used the same warm executable, sequentially alternating baseline/candidate,
with no cache flush, network, node, datadir, or polling sleeps. Host load was
not controlled. Bash `time` includes the observer's child processes.

| Run (1,000 samples) | Baseline wall / system seconds | Candidate wall / system seconds |
| --- | --- | --- |
| 1 | 8.722 / 8.939 | 8.098 / 6.897 |
| 2 | 8.729 / 9.047 | 8.105 / 6.895 |
| 3 | 8.816 / 9.065 | 8.076 / 6.877 |

Median wall cost decreases 7.2%; median system CPU cost decreases 23.8%.
Bash xtrace with `PS4='+${BASHPID} '` confirms the two `printf` producer
processes disappear. This is not a syscall census: ptrace is unavailable in
the sandbox. No end-to-end IBD speedup is established by this microbenchmark.

Reproduce after building `jsonq`:

```bash
ISO_JSONQ_BIN="$PWD/build/bin/jsonq" \
  bash tools/scripts/isolated_node_env_selftest.sh
ISO_JSONQ_BIN="$PWD/build/bin/jsonq" \
  bash tools/scripts/isolated_node_env_selftest.sh --benchmark
```

For the baseline, copy the current selftest and `port_probe.sh` into a scratch
directory alongside `isolated_node_env.sh` extracted from the baseline commit.
Run the same commands against that selftest with the same absolute JSONQ path.
The benchmark is optional; the existing `check-shell-host-assumptions` gate
continues to run the ordinary selftest.

The expanded fixtures cover multiline replies, a 128 KiB padding field, and
truncation after that field, in addition to existing refusal cases for RPC
failure, missing error, string/boolean/negative/fractional/exponent results,
malformed documents, and readiness/peer-listener outcomes. All pass against
both baseline and candidate. Port-probe, service-argument, and peer-tip
selftests also pass. Bash syntax checks and `git diff --check` pass.
The C23 lint runtime was compiled directly from the Makefile's source list
with strict warnings. Its shell-host-assumptions gate and selftest, full
tracked-file credential scan, no-Python gate, and architecture-tree gate pass.

Candidate source SHA-256:

- `isolated_node_env.sh`: `8ef13b4901a97c33c19ebf9b6259e9a7f92cabba74a5baeece3300848a7b0a68`
- `isolated_node_env_selftest.sh`: `c39e5ec16ba78133cc7b84670d075c23b0f74e2d8374aa1c54bb42757167611f`

The normal `make jsonq` path entered Tor preparation and failed to register
its submodule because `.git/config` is read-only; the remaining build was
interrupted. Direct compilation of the standalone parser allowed the focused
checks above. Full node build, live startup/resume, and time-to-tip acceptance
remain unmeasured in this slice. No production operations were performed.

The original publication attempt was blocked: `git commit --only` for these
three files could not create `.git/index.lock` on the read-only filesystem. Refresh also encountered
a read-only `.git/FETCH_HEAD`; direct remote inspection encountered unavailable
GitHub DNS. No commit or push was completed. The branch remains
`agent/worldstream-ibd-20260918`; unrelated staged work must stay excluded when
the supervisor commits this slice.

## Requalification on 2026-09-19

The pending slice was kept separate from the checkout's other staged and
unstaged work. A deterministic producer-count regression now instruments one
successful observation: the baseline fails with four `printf` calls, while
the candidate passes with only the fixture RPC and result writes. The original
semantic fixtures pass against both versions; the new performance regression
fails only against the baseline. The parser and both typed checks are unchanged.

Three alternating 1,000-sample runs, using the same directly compiled C23
parser and local response fixture as above, measured:

| Run | Baseline wall / system seconds | Candidate wall / system seconds |
| --- | --- | --- |
| 1 | 8.820 / 9.128 | 8.033 / 6.872 |
| 2 | 8.738 / 8.995 | 8.159 / 7.081 |
| 3 | 8.834 / 9.092 | 8.049 / 6.827 |

Median observer wall time decreased 8.7%; median system CPU decreased 24.4%.
Host load was uncontrolled; no time-to-tip or live-node claim follows.
Port-probe, service-argument, peer-tip, shell-host-assumptions (including its
selftest), architecture-tree, no-Python, and secret-printf checks pass. Bash
syntax and both staged and unstaged whitespace checks pass. The parser compiled
with GCC 14.2.0 and the Makefile's strict C23 warning flags.

The updated selftest SHA-256 is
`68ff6fa17486681e8c3996a58a9896f341f61727c7c05cb9a9ba6c54a1be3c3a`.
No runtime, consensus, validation, or acceleration-policy file belongs to this
slice. Its publication set is exactly this record, `isolated_node_env.sh`, and
`isolated_node_env_selftest.sh`.

The full tracked-file credential scan reports zero violations across 8,032
files. The consensus seal check passes for all 554 sealed files and 80
sections. The standalone development-branch fetch succeeds and observes the
same baseline SHA locally and remotely; `origin/main` is absent on this origin.

`make lint` was attempted, then interrupted during prerequisite setup before
the lint gates ran; it is not a passing full-lint result. The focused gates
above ran directly with the available lint binary. The new `git commit --only`
attempt also failed to create `.git/index.lock` on the read-only filesystem.
No commit or push was completed in this requalification. The supervisor must
retain the exact three-file scope when publishing from a writable checkout.
