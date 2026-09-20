<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: retain interrupted preflight connections

Branch: `agent/worldstream-ibd-20260918`; HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The C3 cold-sync file-service preflight discarded a pending connection whenever
its writable wait returned EINTR. This could reject an available fixture or
spend the remaining budget on another address before an IBD trial even began.
The probe now retries the same socket after an interruption, recomputing the
remaining original deadline. Other wait failures and pending socket errors
still reject the connection. The authenticated handshake remains required.

## Reproduction and measurement

Linux x86_64, kernel 6.8.0-139-generic, GCC 14.2.0. The regression compiles the
actual probe helpers with real platform types and deterministic clock/socket
substitutions. No network, node, credentials or datadir participates.

The first endpoint receives an interruption at 250 ms and becomes writable
after another 250 ms. The second endpoint is silent. The total budget is
1,000 ms. These are fixture-clock observations, not host wall-time benchmarks
or measured real-chain synchronization improvements.

| Observation | Entry baseline | Candidate |
|---|---:|---:|
| Connected | No | Yes |
| Elapsed fixture milliseconds | 1,000 | 500 |
| Connection attempts | 2 | 1 |
| Writable waits | 2 | 2 |

The baseline fails the new regression. Additional cases cover a single
endpoint, repeated interruptions exhausting the original budget, hard wait
failure, pending connection failure with fallback, and ordinary readiness.

## Validation

```sh
bash tools/scripts/fs_handshake_probe_interrupt_selftest.sh --analyze
bash tools/scripts/fs_handshake_probe_deadline_selftest.sh
bash tools/scripts/stopwatch_handshake_selftest.sh
```

All pass. The modified production translation unit also passes strict C23
compilation with `-Wall -Wextra -Werror -pedantic -fanalyzer`. The full probe
links with the source/dependency list from its Makefile recipe; usage and
invalid-budget paths retain exit status 2 without contacting a peer.
Shell syntax, architecture-tree, shell-host-assumptions, pipefail-status-pipe,
discarded-status and `git diff --check` pass. ShellCheck is unavailable.

`make lint-fast` and `make fs-handshake-probe` each exceeded a 50-second bound
during initialization. The latter also reported read-only Git configuration
while initializing the Tor submodule. The direct compiler/link checks above
are fallback evidence, not a claim that aggregate Make gates passed.

## Scope and publication

This slice adds only the interruption loop, its test invocation comment, the
new interrupt regression and this record. Earlier deadline work in the probe
is preserved. Its entry bytes have SHA-256
`f1f094686063e4f1fd13189eb2fd803643c6a3fa92d182bf2fd1f569a80c81d4`.
The entry snapshot and incremental source patch are under
`/tmp/worldstream-probe-interrupt/`; these are temporary development evidence.
The preexisting staged diff is byte-identical after this work. Do not stage
the entire dirty probe file as though all its changes belong to this slice.

Consensus, cryptographic validation, optional acceleration policy and all
Hetzner-owned runtime, scheduling and database surfaces are unchanged. The
reviewed slice contains no secrets, build products or benchmark output.

Publication is blocked: fetching cannot write `.git/FETCH_HEAD`, and the
remote lookup cannot resolve GitHub. No commit, push or exact remote-SHA
verification occurred. The branch is unchanged. Aggregate lint remains an
unmet integration prerequisite.
