<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream refold observer deadline

Baseline HEAD: `c1f7863d098e1efaa8deba240c580ae0559312a5`, branch
`agent/worldstream-ibd-20260918`. This slice changes only the refold-rate
benchmark observer, its local regression and this note. Earlier staged and
unstaged work is separate and preserved.

The harness called its RPC client without a deadline and ignored exit status.
A stuck client could suspend frontier sampling indefinitely. A client emitting
`{"hstar":999}` before exiting unsuccessfully supplied a false sample and
prevented the alternate CLI form from being tried. This is measurement
correctness and observer latency, not peer scheduling or node reliability.

Each RPC form now has a five-second timeout and one-second TERM-to-KILL grace.
Only successful command output reaches the existing frontier parser. A failed
read reports its exit status on stderr and supplies no sample; the existing
alternate-form fallback remains. Preflight checks for `timeout` before starting
the fixture node. A two-form failed observation can consume about twelve
seconds plus scheduling overhead. The outer sampling cadence and deadline
accounting are unchanged; this does not claim an exact total-run deadline.

## Local evidence

Linux x86_64, Bash 5.2, GNU timeout; isolated shell clients, no sockets or node.
The same fixture exercises native flags and standalone environment arguments.
Timing uses Bash `SECONDS` and is descriptive, not a performance assertion.

| Observation, for each client mode | Baseline | Changed |
|---|---|---|
| Failed command with height prefix | height 999 accepted | no sample |
| Failed first form, successful alternate | height 999 accepted | height 73 |
| TERM-resistant client, finite eight-second sleep | 8 s, height exposed | 6 s, no output |
| Successful observation after failure | height 42 | height 42 |

The baseline fails the regression. The changed harness passes success, empty,
failed, partial, alternate-form, TERM-resistant timeout and recovery cases in
both modes. The regression also counts timeout invocations and checks their
configured bounds, without grading a wall-clock threshold. It is wired into
the harness's existing `--selftest`, whose 22 existing parser cases and seven
rate-verdict cases pass. Applying only this slice to clean HEAD also passes
the new observer regression, independently of earlier pending parser edits.

Reproduce without a node:

```bash
bash tools/scripts/step1_refold_rpc_selftest.sh
bash tools/scripts/step1_refold_rate_proof.sh --selftest
# The first command accepts an optional saved baseline script path.
```

No end-to-end IBD or sovereign-validation speedup was measured. A successful
command still passes through the existing parser; this change does not add
general JSON or JSON-RPC envelope validation.

## Validation and boundaries

Bash syntax, discarded-status, pipefail-status, shell-host-assumptions,
wall-clock-assertion and architecture-tree checks pass. ShellCheck is absent.
No compiled source changes. `make -j4 lint-fast` was bounded to 50 seconds and
timed out during setup, before an aggregate verdict; full lint is not claimed.

Consensus source, validity rules, cryptographic semantics, wallet state,
peer/block-request scheduling and database behavior are untouched. Optional
acceleration and independent validation authority are unchanged. Fixtures use
temporary files only. No credentials, datadirs, logs, caches, generated output
or binaries belong to this slice.

Publication is incomplete. Fetching the development branch cannot write
`.git/FETCH_HEAD`. Preparing the isolated commit index cannot create the
harness blob in the read-only Git object store. Origin lookup also fails DNS.
No commit, push or independently verified remote SHA is claimed. The exact
isolated patch is saved at `/tmp/worldstream-refold-slice/slice.patch`; it
excludes all pre-existing changes. Finish aggregate validation and publish
only the development branch when Git metadata and origin access are writable
and reachable. The original staged patch, excluding this slice's new test,
was compared byte-for-byte with its entry snapshot and is unchanged.
