<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: bounded scalar reads in the fold observer

The drive reader in `tools/scripts/fold_profile.sh` copied the remainder of
each telemetry line into each scalar regex. Eight ordinary counters followed
by 50,000 diagnostic fields handed 9,823,247 bytes to eight regex calls.
This is instrumentation overhead; no end-to-end IBD speedup is claimed.

Scalar matches now start at the exact literal key with a key-plus-32-byte
window, growing when the integer reaches its edge. The reader still searches
the entire line for duplicates, preserves the last valid value on the first
matching line, and retains wide integer text without numeric conversion.
Stage triples retain their existing matching and duplicate policy.

Measured on Linux x86_64, AMD EPYC 7402P, 48 logical CPUs, GNU awk 5.2.1.
Synthetic local telemetry, warm tools/filesystem, uncontrolled host load;
no node, peer, credentials or datadir. Each timing is 100 uninstrumented reads.

| Diagnostic fields | Before regex bytes | After regex bytes | Before wall | After wall |
| --- | ---: | ---: | ---: | ---: |
| 0 | 943 | 413 | 0.50 s | 0.51 s |
| 500 | 83,215 | 435 | 0.54 s | 0.53 s |
| 50,000 | 9,823,247 | 435 | 4.63 s | 3.81 s |

The large fixture took about 18% less wall time in this observation. Timing
is descriptive. The regression gates exact results and a deterministic
512-byte regex-input ceiling for these eight ordinary scalar fields, rather
than a host-dependent time threshold. Longer integers may grow the window.
The baseline fails that ceiling.

Reproduce with:

```sh
sh tools/scripts/fold_profile_drive_window_selftest.sh --bench
make -j2 fold-profile-selftest fold-profile-summary-selftest
```

The new regression is included in `fold-profile-selftest`. It also covers
31–65 and 1,000-digit values, negative values, repeated requested keys,
malformed duplicates, numeric prefixes and first-line selection. The new
regression and complete drive CSV test pass with GNU awk, mawk and BusyBox awk.
POSIX shell and bash syntax checks pass. The profiler and summary Make targets
pass. Scoped lint passes: core seal, architecture tree, pipefail status pipes,
discarded statuses and no-Python. `git diff --check` passes.

The starting checkout was already extensively dirty at HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, on
`agent/worldstream-ibd-20260918`. Before-source SHA-256:
`d1a0f1667f5ea8da9866c90aea35bb1121d68442db328153ae58ac83116915b4`.
After-source SHA-256:
`fda21900aba1399bcc05c2285959b0d808b2e84360ef1b6653dc6d29ba1d16c0`.
These identify the actual working files, not clean committed baselines.

This slice changes only the profiler, its regression, one Make recipe entry
and this record. Existing edits remain intact. Consensus, validation,
optional-acceleration policy and Hetzner-owned runtime code are unchanged;
the core seal passes. No secrets or benchmark artifacts are part of the slice.

Publication remains blocked: the sandbox mounts `.git` read-only (fetch
cannot write `FETCH_HEAD`), and remote lookup cannot resolve GitHub. The
public build also reports a Tor submodule registration failure on read-only
`.git/config`. Full build and lint attempts were interrupted after making no
further progress; neither is claimed green. No commit, push or remote-SHA
verification was possible in this run.
