<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: fail closed before benchmark cookies reach the shell

## Scope and baseline

Worldstream checkpoint `0b29bec272fd4b2b674e98022f6c4bd524ca3b1f`
reads the fresh-sync node's private `.cookie` and interpolates it into curl's
shell command. The reader rejected empty, oversized, late, and failed reads,
but accepted every other byte sequence. The existing startup fixture proved
that baseline by successfully admitting the arbitrary value
`fixture:fixture`; replacing it with quote or command-substitution bytes took
the same path to `popen`.

This is an evidence-runner safety defect, not a measured chain-processing
bottleneck. A malformed or replaced cookie could acquire shell syntax in the
benchmark process. No credential bytes were logged, and the node's ordinary
producer was not defective.

## Root cause and change

The benchmark launches `zclassic23` without `-rpcuser` or `-rpcpassword`, so
its only valid credential shape is owned by `rpc_http_auth_configure`:
`__cookie__:` followed by exactly 32 lowercase hexadecimal digits. The
observer did not enforce that producer/consumer contract before constructing
the curl command.

`read_cookie` now accepts exactly that shape, rejects everything else, and
clears rejected bytes. The focused startup regression covers the valid token
with and without a final newline, plus an empty token, oversized reads, the
wrong user, short and long secrets, uppercase hex, shell metacharacters, a
control byte, an embedded NUL, and data after a newline. The timing,
interrupted-wait, and deadline fixtures use the real producer shape so their
existing behavior remains covered.

Reproduce with:

```sh
bash tools/scripts/bench_fresh_sync_startup_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_startup_interrupt_selftest.sh --analyze
bash tools/scripts/bench_fresh_sync_startup_budget_selftest.sh
bash tools/scripts/bench_fresh_sync_startup_late_selftest.sh
bash tools/scripts/bench_fresh_sync_startup_sleep_selftest.sh
make bench-fresh-sync-selftest
```

This changes only benchmark credential admission. Node authentication,
validation, networking, peer scheduling, storage, wallet behavior, and
Zclassic consensus are unchanged.
