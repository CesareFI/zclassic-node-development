<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream optional bootstrap flush scope

Base: `c1f7863d098e1efaa8deba240c580ae0559312a5` on
`agent/worldstream-ibd-20260918`. Owned surface: the optional bundle courier
and its isolated shell regression. No node, consensus, peer scheduler,
database tuning, or validation code changes.

## Problem and bounded change

After hashing the source, copying, making the destination read-only, checking
its hash, and renaming it, the courier called `sync` with no arguments. That
flush encompasses unrelated filesystems as well as the bundle filesystem,
coupling bootstrap completion to unrelated storage work.

The courier now first requests `sync -f` on the bundle directory. This flushes
the containing filesystem, including the file, rename, and newly created
parent directories. Unsupported or failed targeted flushes fall back to the
original global, best-effort flush. It still may wait for unrelated writes on
the **same** filesystem. Hosts without targeted sync retain the old cost.

Both SHA3 checks, corruption refusal, read-only staging, atomic rename, cleanup,
and already-staged/installed guards remain in place. Byte delivery grants no
trust: normal install-time checks and independent validation are unchanged.
Optional acceleration remains optional.

## Evidence and limits

Linux x86_64, Bash 5.2.21, GNU coreutils 9.4, OpenSSL 3.0.13; local ext4 scratch
directories, no peers, no live node or production datadir. A warm-cache 1 MiB
zero-filled inert source was delivered into a fresh directory on each run.
Five wall-time observations with `/usr/bin/time -f '%e'` were:

| Courier | Seconds |
|---|---|
| Original | 0.06, 0.05, 0.05, 0.05, 0.05 |
| Targeted flush | 0.06, 0.05, 0.05, 0.05, 0.05 |

There is **no measured end-to-end improvement on this idle fixture**, and no
IBD or time-to-tip speedup claim. The deterministic regression measures the
scope change: one global flush becomes one filesystem-targeted flush and
zero global flushes when supported. Cross-filesystem contention latency is
not qualified here. Syscall tracing was unavailable because ptrace is denied.

The regression executes the actual courier with real SHA3 hashing and copying,
using a recording sync substitute. It fails against the original source with
`expected one filesystem flush`, and passes the changed source. It checks
nested directories and spaces, unsupported and failed flush fallbacks,
read-only identical delivery, already-staged/installed guards with a missing
source, corrupt-copy refusal, and temporary-file cleanup.

Reproduce without a node or chain fixture:

```bash
bash tools/scripts/bundle_bootstrap_flush_selftest.sh
# Optional argument: a saved pre-change courier; this must fail the scope check.
bash tools/scripts/bundle_bootstrap_flush_selftest.sh /tmp/bundle-before.sh
bash tools/scripts/cold_start_to_tip_probe.sh --selftest
```

The focused regression and existing cold-start selftest pass in an isolated
checkout of the base plus this slice. Bash syntax, pipefail-status,
discarded-status, and shell-host-assumption checks pass. The core-seal mirror
check passes; no core files change. `make lint` was attempted in the original
workspace with a 120-second bound, but timed out before a lint verdict; its
output reported missing Tor archives. No full-lint pass is claimed. No C
source changes, so a C compiler or consensus acceptance run cannot establish
any additional claim about this shell-only slice.

The original workspace contains extensive unrelated changes and read-only
Git metadata. Integration uses a separate writable checkout of the same
development branch and copies only this courier, regression, and note. No
secrets, generated files, logs, caches, binaries, or benchmark output are part
of the slice. Original staged and unstaged changes remain byte-identical.
