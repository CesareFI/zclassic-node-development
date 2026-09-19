# Peer selection latency

## Sparse address tables (2026-09-19)

`CAddrMan::Select_()` searched a sparse new or tried bucket table with a bounded
random walk. After every 1,000 empty slots it slept for 100 milliseconds while
holding the address-manager lock. A deterministic local regression containing
one new address and one tried address exercised the production path with a
nonzero bucket key:

| Two selections | Before | After |
| --- | ---: | ---: |
| Wall time | 30.53 s | 0.10 s |
| User CPU | 0.09 s | 0.08 s |
| System CPU | 0.02 s | 0.01 s |

Times include test-process startup and fixture setup. They measure sparse peer
selection latency, not network connection time or total node startup.

The selection path no longer sleeps between probes. It retains the same initial
bucket and position draws, random-walk updates, 200,000-retry bound, new/tried
choice, address chance weighting, and return behavior. The bounded search now
lives in a shared helper instead of two nested copies. `pmccabe` measured
`CAddrMan::Select_()` at 11 after the change, down from 20; the extracted helper
measures 4. Explicit sequential random draws avoid C++11's unspecified function
argument evaluation order.

Validation:

- All 14 addrman Boost cases passed (189 assertions), including the existing
  deterministic selection-sequence checks and the new sparse new/tried case.
- 83 broader networking, DoS, bootstrap protocol, validation, and database
  cases passed (46,072,059 assertions).
- The healthy loopback header-sync scenario accepted its first header in 3.00
  seconds with no header-stall disconnect.
- Valgrind reported zero errors and no definite, indirect, or possible leaks in
  the focused sparse-selection regression.
- GCC's static analyzer reported no finding in `addrman.cpp`; its warnings came
  from pre-existing `tinyformat.h` fallthroughs. The daemon and Boost test
  executable rebuilt successfully, and `git diff --check` passed.

The change only removes lock-held waits and consolidates peer selection code.
It does not alter peer table serialization, network messages, chain state,
consensus parameters, transaction or block validity, or cryptographic checks.
