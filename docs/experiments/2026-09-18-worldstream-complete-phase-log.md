<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream completed startup phase scan

The fresh-sync benchmark's incremental phase reader continued reading to the
captured log size after finding all five milestones. The caller already stops
polling once those milestones have timestamps. Returning after the final match
removes unnecessary observer work before the next RPC sample.

This slice adds an early return to `tools/bench_fresh_sync.c`, a regression in
`tools/scripts/bench_fresh_sync_complete_log_selftest.sh`, and one invocation in
`make bench-fresh-sync-selftest`. It depends on the existing, uncommitted
incremental phase reader. Other pending Worldstream changes are outside this
slice. The pre-existing index entries were preserved byte-for-byte. Only the
new regression was added to the index; attempts to unstage it were refused
because `.git/index.lock` could not be created on the read-only filesystem.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including pending changes.
Baseline source SHA-256:
`a7d3807d9c9dfddcda04e6a71898fadd5604b38e3f9038440fdba72fc77d334b`.
Updated source SHA-256:
`b68feb9dd81ebf754714c1068f511f46dd96c36d76fa2d503877100ccf1cb52b`.

Linux x86_64, GCC 14.2.0, ten fresh scanner states reading the same warm
32 MiB temporary file; no node or network. Times are informational, subject to
ambient host load. The regression asserts bytes read and milestone results,
not a wall-clock threshold.

| Final milestone placement | Baseline bytes / ten polls | Updated bytes / ten polls | Baseline seconds | Updated seconds |
|---|---:|---:|---:|---:|
| First 4 KiB | 335,544,320 | 40,960 | 0.305371 | 0.000059 |
| Split across first two reads | 335,544,320 | 81,920 | 0.305671 | 0.000099 |
| Absent | 335,544,320 | 335,544,320 | 0.311068 | 0.311655 |
| End of log | 335,544,320 | 335,544,320 | 0.310927 | 0.311714 |

Reproduce with:

```bash
bash tools/scripts/bench_fresh_sync_complete_log_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_complete_log_selftest.sh --measure /path/to/baseline.c
```

The baseline fails the first bounded-read assertion without `--measure`.
The production reader compiled with C23 `-Wall -Wextra -Werror` and GCC
`-fanalyzer`. Existing phase boundary, append, replacement, truncation,
read-failure and bounded-growth tests pass. Startup, command-output, HTTP
deadline, benchmark-outcome and height-demand fixtures also pass, as do the
triple-run and evidence-judge selftests.

The timestamp fixture fails on both baseline and updated source: it expects
completion at 21 seconds, but the existing height-demand optimization produces
19 seconds. No assertion was changed. The full benchmark links with its
shipped flags; both sources emit the same seven existing diagnostics (five
ignored `system` results and two certificate-copy truncation warnings).

Architecture, discarded-status, pipefail-status, no-wallclock-assertion,
no-API-keys, no-Python, shell syntax and whitespace checks pass. All 554 sealed
core files and 80 sections verify, and the exported seal mirror matches.
Consensus, independent validation, optional acceleration, peer scheduling,
database tuning and node runtime behavior are unchanged. This measures
observer work only; no end-to-end IBD speedup is claimed.

Publication remains incomplete. The node build could not initialize Tor
because `.git/config` writes were refused; it was interrupted after making no
further visible progress. The Make selftest and lint-fast aggregates each hit
a 50-second bound during setup without reaching their recipes. Fetching the
development branch fails on read-only `.git/FETCH_HEAD`, and querying origin
fails GitHub DNS resolution. Adding the new test to the index succeeded, but
the later index-restoration attempts failed. No commit, push, upstream integration or remote-SHA
verification is claimed. No secrets, datadirs, logs, caches, binaries or
temporary benchmark output are part of this slice.
