<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: refuse DNS work for expired cold-sync preflights

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The cold-sync fixture preflight checked its deadline only after `getaddrinfo`.
If socket-runtime initialization or descheduling exhausted the budget before
`probe_connect` began, it still entered the blocking resolver. An eight-line
guard now reports expiry and returns the existing unreachable result before
resolution. Requests with time remaining follow the existing path.

## Reproduction and measurement

Linux x86_64, GCC 14.2.0, C23 with `-O2 -Wall -Wextra -Werror -pedantic`.
The test compiles the actual connection helpers, substitutes the monotonic
clock and resolver, and refuses real socket creation. No node, datadir, peer,
DNS service or network connection participates. The resolver advances the
fixture clock by 4,000 ms; this is a deterministic cost model, not measured
DNS latency or an end-to-end IBD speedup.

| Already-expired preflight | Baseline | Candidate |
|---|---:|---:|
| Resolver calls | 1 | 0 |
| Added simulated milliseconds | 4,000 | 0 |
| Socket opens | 0 | 0 |

Both pristine HEAD and the working source at entry reproduce the resolver
call. The regression fails against that entry source and passes with the
guard. It also checks a past deadline, exactly exhausted resolution, slow
resolution, a one-millisecond live budget, resolver errors and cleanup.
Resolution started while the budget is live can still exceed the deadline;
this change does not claim to bound active DNS.

## Validation

```sh
ANALYZE=1 bash tools/scripts/fs_handshake_probe_resolver_selftest.sh
bash tools/scripts/fs_handshake_probe_deadline_selftest.sh
bash tools/scripts/fs_handshake_probe_interrupt_selftest.sh --analyze
```

All three pass. GCC analysis of the resolver and interrupted-wait fixtures,
production-source syntax checks, and a standalone link using the existing
Makefile's probe sources and C23 warning flags pass. Architecture-tree,
shell-host-assumption, pipefail-status and discarded-status gates pass.
Bash syntax and `git diff --check` pass. `make lint` reached its 50-second
bound during initialization; a full lint pass is not established.

The change is confined to benchmark preflight admission and its tests.
Consensus and cryptographic sources are unchanged; normal independent
validation remains authoritative, and optional acceleration policy is
unchanged. No Hetzner scheduling, database or runtime surface changed.
The reviewed slice contains no secrets, datadirs, logs, binaries or generated
output. The linked probe and snapshots reside only under
`/tmp/worldstream-expired-resolver/`.

## Existing work and publication

The entry working probe already contained separate deadline and interrupted
wait changes. Its SHA-256 was
`048c0d0d1f62f929b3c03bd3f15cc54b280a3560eb7ba084e6d0cc51961275ee`.
This slice adds only the expiry guard and the new test invocation there,
adds the resolver regression, and adjusts one existing deadline-test cleanup
expectation: no resolver allocation means no `freeaddrinfo` call. Earlier
staged, unstaged and untracked work is preserved. Do not commit the entire
dirty probe or adopt the pre-existing untracked deadline test as new work.

Publication remains incomplete. Origin has no `main` ref; fetching the named
Worldstream branch cannot write the read-only `.git/FETCH_HEAD`, and a later
remote SHA lookup fails GitHub DNS resolution. No commit, push or verified
remote SHA is claimed. Full lint and publication still require a working
environment. The branch remains unchanged.
