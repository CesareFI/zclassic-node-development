<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reserve a distinct datadir for each cold-start measurement

Branch: `agent/worldstream-ibd-20260918`; entry HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The fresh-sync benchmark named its datadir using a timestamp with one-second
resolution and ignored the result of `mkdir`. Two launches in the same second,
or a repeated wall-clock timestamp, therefore selected the same datadir. A
second launch could encounter the first node's lock or previous chain state,
cookie and log. Such a trial cannot establish fresh-datadir time to tip.

The benchmark now reserves its timestamp-prefixed directory with `mkdtemp`,
checks creation before starting the child, and rejects missing/empty HOME,
unrepresentable timestamps and truncated paths. Directory creation requests
mode 0700. Prior-run state is preserved. Fixed benchmark ports are unchanged;
this change does not make simultaneous node trials on those ports possible.

## Reproduction

The baseline is the already-modified entry source, SHA-256
`353594969deac21751fe755209ad293e7cb11f09fd736f9e997be246578c4ead`,
not pristine HEAD. Linux x86_64, GCC 14.2.0. The regression compiles the actual
setup block, fixes the clock, substitutes binary availability and HOME, and
uses real directory creation within a disposable fixture. No node, peer,
production datadir or credential is used.

| Two same-second setup calls | Baseline | Candidate |
|---|---:|---:|
| Distinct datadirs | 1 | 2 |
| Second setup selects prior-run data | Yes | No |

The baseline fails the distinct-directory assertion. The candidate also
preserves a sentinel in the first directory, leaves it absent from the second,
checks directory modes, and refuses invalid setup inputs. This establishes
benchmark isolation, not faster block processing or measured end-to-end IBD
speedup. No discarded-trial wall time was measured.

## Validation

Passing commands:

```sh
bash tools/scripts/bench_fresh_sync_datadir_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_output_selftest.sh --analyze
make bench-fresh-sync-selftest bench-fresh-sync-height-selftest
make bench_fresh_sync
```

The new regression is registered in `bench-fresh-sync-selftest`. Its extracted
production code passes C23 compilation with `-Wall -Wextra -Werror` and GCC
`-fanalyzer`. Shell syntax, architecture-tree, pipefail-status, discarded-status,
shell-host-assumption checks and `git diff --check` pass. The new untracked
script is also checked explicitly for discarded shell status.

Full-source strict compilation reports the same seven pre-existing diagnostics
in baseline and candidate: five ignored `system` results and two potentially
truncated certificate-copy commands. These are not waived or claimed fixed.
`make lint-fast` exceeded a 50-second bound during initialization, so no
aggregate lint pass or publication readiness is claimed.

Only benchmark setup, its regression, one test-suite registration and this
record belong to the slice. Consensus, cryptography, validation, acceleration
policy, node runtime, peer scheduling and database behavior are unchanged.
No secrets, datadirs, logs, caches, binaries or generated artifacts belong to
the slice. Existing staged and unstaged work is preserved.

Publication is incomplete: fetching cannot write `.git/FETCH_HEAD` on the
read-only filesystem, and remote lookup fails resolving GitHub. Staging the
two new files succeeded; not every Git metadata operation is blocked. No commit,
push or remote-SHA verification is claimed. Entry snapshots, validation output
and a separate slice patch are under `/tmp/worldstream-fresh-datadir/`.
