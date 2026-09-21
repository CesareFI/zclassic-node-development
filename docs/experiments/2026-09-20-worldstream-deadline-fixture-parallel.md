<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream fresh-sync deadline fixture wall time

Branch: `agent/worldstream-ibd-20260918`; baseline HEAD:
`0b29bec272fd4b2b674e98022f6c4bd524ca3b1f`.

## Bottleneck and baseline

The hermetic fresh-sync HTTP deadline regression ran six independent stalled
observer cases serially. Each case intentionally waits for the production
two-second curl deadline, so the fixture alone took 12.29 seconds wall time
(0.18 user, 0.10 system) and accounted for roughly one third of the measured
36.66-second aggregate fresh-sync self-test.

The cases cover silent and partial RPC responses, explorer readiness, and
explorer page-size observations. They share no mutable fixture state: every
observer launches its own controlled curl stand-in, receives its mode through
its process environment, and checks only its own elapsed time and result.

## Change and measurement

The fixture now forks one bounded child per deadline case and waits for all six
statuses. Each child retains the exact production observer call, two-second
timeout, false-observation assertion, empty partial-RPC buffer assertion, and
one-to-four-second scheduling tolerance. A failed or signaled child names its
mode and fails the parent fixture.

Reproduce the focused measurement with:

```sh
/usr/bin/time -f 'wall=%e user=%U sys=%S' \
  bash tools/scripts/bench_fresh_sync_deadline_selftest.sh
bash tools/scripts/bench_fresh_sync_deadline_selftest.sh --analyze
```

On this Linux x86_64 host the candidate took 2.31 seconds wall time (0.19 user,
0.13 system), an 81% wall-time reduction. All six cases still measured
2.003--2.004 seconds and rejected their silent or partial response. GCC static
analysis and Bash syntax validation passed. The complete
`make bench-fresh-sync-selftest` front door passed in 26.74 seconds versus the
36.66-second baseline, a 27% wall-time reduction with the same constituent
coverage.

This changes only hermetic benchmark regression scheduling. It starts no node,
contacts no network peer, reads no datadir, and changes no production C,
observer deadline, chain data, validation predicate, proof of work, monetary
rule, activation height, serialization, or cryptographic semantics. Optional
Z23 acceleration and authoritative independent Zclassic validation are
unchanged.
