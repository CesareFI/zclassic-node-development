<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream cold-start command observations

The cold-start benchmark accepted partial command output and ignored command
exit status. A failed RPC command could therefore supply a parseable
`"state":"at_tip"` prefix to the time-to-tip observer. This slice corrects
measurement integrity; it does not establish an IBD speed improvement.

The initial suspected bottleneck was a pipe deadlock on oversized responses.
The local reproduction disproved that hypothesis: `pclose` closed the pipe,
the writer failed, and the reader still returned the captured prefix as a
successful observation. With a 32-byte buffer and a 1 MiB producer, the
baseline returned 31 bytes; the corrected reader returns zero and clears the
output. Exact-fit successful output remains accepted.

Baseline: branch `agent/worldstream-ibd-20260918`, HEAD
`c1f7863d098e1efaa8deba240c580ae0559312a5`, including the pre-existing
uncommitted Worldstream changes. Baseline `tools/bench_fresh_sync.c` SHA-256:
`e9ad2cb5bd0de533fe9c915b8ec7a272fddc9259883b2949cd3dc3b2768f08fb`.
Updated SHA-256:
`2ee846dfb2e315e1f65d83ec36e9bba11ffcd8fb1a5fe1f382db1bbf057b3e95`.

`run_cmd` now checks one additional byte, stream errors, and command status.
An oversized or failed observation is discarded, with a diagnostic that omits
command text because RPC commands can contain credentials. It does not drain
unbounded output. Existing command-duration behavior remains unchanged:
this is not a network timeout or a general bounded-process executor.

Reproduce without a node, network, wallet, or datadir:

```sh
bash tools/scripts/bench_fresh_sync_command_selftest.sh --analyze
make bench-fresh-sync-selftest
```

The optional final argument selects a saved baseline source file. On Linux
x86_64 with GCC 14.2.0 the baseline fails the oversized-output assertion.
The updated fixture passes empty, short, exact-fit, oversized, unsuccessful,
signal-terminated, false-tip, and one-byte-buffer cases. Mutations removing
either the size refusal or status refusal fail. The extracted production
helpers compile as C23 with `-Wall -Wextra -Werror` and GCC `-fanalyzer`.
The complete standalone tool builds with its shipped flags; pre-existing
warnings in `main` concern ignored `system` results and copy-command sizes.

The phase-log regression, stopwatch judge, artifact-symmetry suite,
architecture gate, shell-host check, no-API-keys check, no-Python check and
`git diff --check` pass. The core seal verifies all 554 files and 80 sections;
the exported core-root mirror matches. No consensus, validation, optional
acceleration policy, runtime, peer scheduling, or database behavior changes.

`make lint-fast` completed with four failures: injected `.agents`/`.codex`
root entries; existing phase-log changes raising `main` complexity above its
pin; 18 stale flag first-use pointers in the dirty tree; and a Windows guard
fixture attempting to create a directory outside the writable roots.
No threshold or assertion was weakened. Make also reported an unavailable
zlib download because GitHub DNS failed; focused tests still completed.

This slice adds only the command-reader change, its new fixture, one invocation
in the existing Make selftest target, and this note. The pre-existing staged
index is unchanged, and earlier working changes are preserved. Generated
artifacts, binaries and temporary test output are not part of the slice.
Publication is incomplete: Git metadata is read-only and the origin query
cannot resolve GitHub. No commit, push, upstream integration, or remote-SHA
equality is claimed.
