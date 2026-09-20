<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: skip unrelated peer version queries in the join clock

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. Owned surface: the shell join benchmark's
PEERED observation, its hermetic regression, and this record.

`ux_join_drill.sh` reparsed the full peer response for both address and version
on every visited peer. Only an address matching the operator-named peer can
complete the clock. Moving the version query into that existing match branch
removes one parser process and full-response parse per unrelated peer.
Address matching, handshake qualification, first-match selection, timestamping,
deadlines, and error handling remain unchanged.

The baseline passes all eight selection fixtures but fails two new exact query
budgets. The candidate passes both selection and work budgets. Cases cover no
matching peer, an empty list, first/last matches, incomplete handshakes, JSON-RPC
wrapping, escaped addresses, and malformed input. The test extracts the actual
observer loop and uses the real JSON parser with a synthetic CLI response;
unexpected sleeping or defect reporting fails. No node or messages are sent.

## Measurement

AMD EPYC 7402P, Linux x86_64, Bash 5.2.21, GCC 14.2.0, warm tools and ordinary filesystem
caches, uncontrolled ambient load. The JSON query executable was compiled from
the base commit with C23, `-O2 -Wall -Wextra -Werror -pedantic`, using the
unchanged in-tree parser sources. Earlier uncommitted JSON-tool optimizations
are excluded. Each run observes 10 identical synthetic 132,102-byte responses:
64 unrelated peers with diagnostic padding, then the requested peer.
Baseline and candidate run sequentially, alternating for three repetitions.

| Observer measurement | Baseline | Candidate |
|---|---:|---:|
| Query processes per poll | 133 | 69 |
| Wall seconds, repetition 1 | 12.13 | 6.34 |
| Wall seconds, repetition 2 | 12.14 | 6.41 |
| Wall seconds, repetition 3 | 12.10 | 6.38 |

Median observer wall cost fell about 47%. This is a stress fixture for
instrumentation overhead, not a live IBD speedup or time-to-tip measurement.
The full-response address queries remain; selecting the first peer avoids
none of the version work and has the same query count as before.

Reproduce with a built `jsonq` (override its path with `ZCL_JSONQ`):

```sh
bash tools/scripts/ux_join_peer_scan_selftest.sh
bash tools/scripts/ux_join_peer_scan_selftest.sh --bench
bash tools/scripts/ux_join_peer_scan_selftest.sh --bench /path/to/baseline.sh
```

## Validation and scope

The focused regression, `two_node_peer_tip_selftest.sh`, and
`isolated_node_env_selftest.sh` passed in a clean temporary checkout of the
base plus this slice. Bash syntax and `git diff --check` passed.
Architecture-tree, discarded-status, pipefail-status-pipe and
shell-host-assumptions gates passed there with the new test staged.
`make lint-fast` in the original checkout exceeded a 55-second bound during
initialization; no aggregate lint pass is claimed. ShellCheck is unavailable.
There are no production C changes requiring node compilation or chain replay.

The exact slice changes no consensus, cryptography, validation, acceleration
policy, scheduling, database or node runtime code. No secrets, generated
artifacts, binaries, logs or datadirs belong to the slice. Existing staged and
unstaged work in the original checkout is preserved. Its `.git` is read-only,
so the isolated commit is prepared in
`/tmp/worldstream-join-observer/review` on the same development branch.
GitHub DNS resolution currently prevents branch fetch and remote verification;
publication must not be inferred from the local commit.
