<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: isolate local sync observers from ambient proxies

Scope: `tools/bench_fresh_sync.c`, its routing regression and Make target.
Base: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. The shared checkout contains other pending
work; this slice was also built and tested independently from that base.

## Problem and measurement

RPC state, explorer readiness and explorer size are loopback observations of
the benchmark child. Curl inherits `http_proxy`, `https_proxy` and `ALL_PROXY`
unless a bypass applies. An operator's proxy environment therefore introduces
an unrelated connection and potential wait into local sync measurement, or
makes a healthy local endpoint unavailable to the observer.

On Linux x86_64, GCC 14.2.0 and curl 8.5.0, the regression extracted the three
production observer functions and exercised their actual curl arguments.
Only destinations were substituted: closed loopback port zero for failure
tests and local files for successful responses. A SOCKS proxy was explicitly
configured on closed loopback port zero, with empty `NO_PROXY`/`no_proxy`.
Curl's verbose routing trace provided the observation, without a node,
listener, external peer, real credential or production datadir.

| Source | Observers | Inherited proxy routes |
| --- | ---: | ---: |
| Base | 3 | 3 |
| This slice | 3 | 0 |

The new default regression fails against the base. The change adds
`--noproxy '*'` to all three curl commands. Their destinations remain fixed
loopback addresses. This removes the extra routing dependency; no elapsed IBD
speedup or time-to-tip result is claimed. Closed ports fail immediately in
this fixture, so it does not simulate a slow proxy or quantify proxy latency.

## Reproduction and validation

```sh
make bench-sync-proxy-selftest
bash tools/scripts/bench_fresh_sync_proxy_selftest.sh --analyze
git show c1f7863d098e1efaa8deba240c580ae0559312a5:tools/bench_fresh_sync.c > /tmp/observer-before.c
bash tools/scripts/bench_fresh_sync_proxy_selftest.sh --baseline /tmp/observer-before.c
```

The extracted observers compile with C23, `-Wall -Wextra -Werror`; GCC
`-fanalyzer` passes. Closed endpoints produce no readiness evidence, while
local file fixtures preserve RPC text, readiness and the exact 13-byte page
count. `make bench_fresh_sync` builds the standalone tool from the isolated
base plus this slice, with existing warnings in unrelated setup code.

Compatibility checks in the shared working tree also pass: command-output,
deadline, readiness, page-size, explorer-scan and ambient-curl-config
selftests. Those checks cover existing pending improvements and are not
claims that those improvements are included in this commit.

Five scoped lint gates pass: shell-host assumptions (including its fixture
suite), bare temporary fixtures, architecture tree, shellouts and retired
agent protocol. `git diff --check` passes. Full `make lint` was attempted but
did not complete: dependency downloads could not resolve GitHub, and the
60-second bounded invocation expired during development-object compilation.
This is not full repository acceptance or a native macOS qualification.

The change leaves consensus, validation, acceleration selection, scheduling,
storage and node runtime sources byte-identical to the base. There is no
deployment. Generated output and temporary traces are excluded from the slice.
