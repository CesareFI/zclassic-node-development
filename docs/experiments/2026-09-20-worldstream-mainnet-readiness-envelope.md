<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream mainnet canary: type RPC readiness

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. This slice owns the isolated-mainnet RPC
readiness decoder, its hermetic regression, Make registration, and this record.
The inherited Worldstream worktree remains separate.

## Bottleneck and baseline

The replay and time-to-tip canaries previously declared RPC ready when
`getblockcount` produced any characters after `tr -dc '0-9-'`. A normal JSON-RPC
warm-up response with error code `-28` and request id `123` therefore became the
nonempty string `-28123`. That ended the readiness wait before the node had
returned a height, moving work and timing into the warm-up interval and making
startup/resume measurements dependent on incidental error and id digits.

The literal baseline fixture reproduces `-28123`. The candidate requires a
complete JSON envelope with `error: null` and a JSON-number result containing
only decimal digits. Height zero is accepted. Errors, strings, booleans,
fractions, exponents, negative values, missing fields, trailing bytes, failed
transport, and malformed input remain not ready. The measured classification
for the warm-up fixture changes from ready to not ready; no polling cadence or
node work changes.

## Validation

```sh
make jsonq
bash tools/scripts/isolated_mainnet_env_selftest.sh
bash -n tools/scripts/isolated_mainnet_env.sh \
  tools/scripts/isolated_mainnet_env_selftest.sh
```

The focused fixture is entirely local: it creates only a temporary empty
directory and overrides the RPC function. It starts no node, opens no socket,
and reads no production datadir. The shell-host-assumptions gate owns the
regression so the parser contract remains part of ordinary lint.

The focused regression, Bash syntax check, scanner selftest, full scanner,
port-probe selftest, regtest isolation selftest, service-argument selftest,
and two-node peer-tip fixture all pass. The aggregate Make front door was
interrupted after more than two minutes without output following unchanged
template generation; its exact owning constituent checks were run directly
and passed. No compiled source changed, so compiler and static-analysis checks
are not applicable to this instrumentation-only slice.

This is benchmark and canary instrumentation only. It changes no C, peer or
block-request scheduling, timeout/reassignment, database tuning, chain data,
validation predicate, proof of work, monetary rule, activation height,
serialization, or cryptographic semantics. Normal independent Zclassic
validation remains authoritative and optional Z23 acceleration is unchanged.
