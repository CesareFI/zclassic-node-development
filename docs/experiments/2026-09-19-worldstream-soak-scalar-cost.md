<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream sync observer: scalar process cost

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. The changed observer was clean at entry;
its SHA-256 was
`202fa77a78a90ae083497e9b365a5540b049ac8a01694cc982b71dbc63c27f89`.
This slice owns only `soak_assert.sh`, its new scalar regression, and this
record. Existing staged and unstaged Worldstream work is separate.

## Bottleneck and measurement

Each ordinary sync-observer poll parsed three numeric fields and one boolean
using separate grep/head/sed pipelines: twelve external program launches,
in addition to the caller's command substitutions. The fallback lag-known
field added another three. Bash's existing regular-expression support now
performs those scalar reads without external tools. The string reader and
every verdict threshold remain unchanged.

Linux x86_64, AMD EPYC 7402P, Bash 5.2.21, warm executable caches. Synthetic
compact health and sync responses; no network, node or datadir. Each sample
runs 200 polls, baseline first and candidate second, including the existing
command substitutions. Ambient host load is uncontrolled; build/check activity
can overlap. Three consecutive repetitions:

| Repetition | Baseline seconds | Candidate seconds |
|---|---:|---:|
| 1 | 4.001 | 1.056 |
| 2 | 3.954 | 1.134 |
| 3 | 3.982 | 1.042 |

Median scalar-observer cost fell about 73.5%, from 19.91 to 5.28 ms per
synthetic poll. This does not establish a real IBD or time-to-tip improvement;
the ordinary observer cadence is 60 seconds. It removes avoidable measurement
overhead without modifying synchronization itself.

## Reproduction and validation

```sh
bash tools/scripts/soak_assert_fields_selftest.sh --bench
LC_ALL=C bash tools/scripts/soak_assert_fields_selftest.sh
bash tools/scripts/soak_evidence.sh --selftest
bash -n tools/scripts/soak_assert.sh tools/scripts/soak_assert_fields_selftest.sh
```

The regression compares both readers with the original pipelines across 21
fixtures: absent/malformed values, duplicate and similarly named keys,
multiline boundaries, control whitespace, boolean prefixes, and integers
beyond shell arithmetic range. Existing text and missing-value behavior are
preserved, including the original space-only trimming. A deterministic
no-external-program test fails on the entry implementation and passes after
the change. Nine complete mocked observer runs cover success, fallback lag
knowledge, unknown lag, excessive lag, missing peers, severity, restart and
missing acceleration-peer reporting. Both C and the host UTF-8 locale pass.
The separate soak-evidence selftest also passes.

Shell syntax, pipefail-status, discarded-status, architecture, shell-host-
assumption, no-API-key and no-Python checks pass. `git diff --check` and its
staged equivalent pass. The native lint tool was compiled from
tracked sources using GCC 14.2, C23, `-O2 -Wall -Wextra -Werror -pedantic`.
`make lint-fast` and `make check-architecture-tree` each exceeded a 50-second
bound during Make initialization; architecture was subsequently checked with
the same native gate directly. No aggregate lint, public-node build or
live-chain acceptance is claimed. ShellCheck is unavailable.

The exact slice contains no consensus, cryptography, peer scheduling,
database, runtime, custody, or acceleration-policy changes. Independent
validation stays authoritative. No credentials, production state, binary,
cache, log, or temporary benchmark output belongs to this slice.

## Publication status

Publication is incomplete. The two source/test paths were staged successfully;
staging this record subsequently failed because `.git/index.lock` is read-only.
A path-scoped commit of just the two staged paths also failed on that lock.
HEAD remains the base named above. The prior staged diff, excluding these two
paths, was compared byte-for-byte with its entry snapshot and is unchanged.
Do not commit the full inherited index as this slice.

Fetching `origin/main` initially reported no such remote ref. Fetching the
development branch then failed on read-only `.git/FETCH_HEAD`. Remote SHA
lookup failed because GitHub could not resolve. There is no new commit or
push, and no remote-SHA equality claim. The supervisor must restore normal
Git metadata writes and remote access to finish publication; no hook or
permission boundary was bypassed.
