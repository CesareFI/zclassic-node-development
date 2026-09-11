# beta6 transaction-rejection diagnostic

Base: original `v2.1.2-beta6`, commit
`14a83d510ffd109d3fa09bf74ebf8c28854a263f`.

This patch adds public transaction metadata to the existing failed
`CheckTransaction` error in `CheckBlock`. It does not identify the cause of the
reported rejection at height 478544 until the diagnostic is collected. The
reported block hash is
`0000000008e4ec6ac2f23b017f38ae68e932a3c2d272ea08c9fbdf75409783a3`;
there is no block-specific logic in the implementation.

The single error line has this format (wrapped here for readability):

```text
ERROR: CheckBlock(): CheckTransaction failed: block=<hash> tx_index=<index> txid=<hash> version=<signed> overwintered=<0|1> versionGroupId=0x<8 hex digits> expiryHeight=<height> vin=<count> vout=<count> joinsplits=<count> sapling_spends=<count> sapling_outputs=<count> valueBalance=<signed zatoshis> reject_reason=<reason> reject_code=<decimal> dos_score=<decimal>
```

The index is zero-based, including coinbase at index 0. The DoS score comes from
the existing const `CValidationState::IsInvalid(int&)` accessor; it is initialized
to zero for non-invalid states. Reasons are passed as data to the existing
type-safe formatter, never as format strings. No transaction serialization,
scripts, keys, memos, or ciphertexts are logged.

Validation order, arguments, first-failure return, validation-state contents,
proof verifier, checkpoint gates, and peer scoring remain unchanged. The indexed
loop visits the same transactions in the same order. The helper accepts const
references and only calls existing logging/hash/state accessors. The format uses
the existing type-safe formatter, so `size_t` counts and signed 64-bit balances
are not narrowed. There are no new manual allocations, pointer ownership,
shared mutable state, or network operations. The failed-block path emits one
bounded metadata record through the existing logger.

## Build on Hetzner using existing beta6 dependencies

From this patched checkout, with the original beta6 dependency prefix already
built for that host:

```bash
ZCL_BETA6_DEPS="$PWD/depends/x86_64-unknown-linux-gnu"
test -r "$ZCL_BETA6_DEPS/share/config.site" &&
test -r "$ZCL_BETA6_DEPS/lib/librustzcash.a" &&
test -r "$ZCL_BETA6_DEPS/include/librustzcash.h" &&
./autogen.sh &&
CONFIG_SITE="$ZCL_BETA6_DEPS/share/config.site" ./configure \
  --enable-hardening --enable-tests --enable-proton=no \
  --with-boost="$ZCL_BETA6_DEPS" \
  CXXFLAGS='-g -O2' \
  CPPFLAGS="-I$ZCL_BETA6_DEPS/include" \
  LDFLAGS="-L$ZCL_BETA6_DEPS/lib" &&
make -C src -j4 zclassicd
```

Output: `src/zclassicd`. This command builds only; it does not start a node or
download/install Rust. It deliberately requires the original proof library;
there is no substitute or validation bypass. For an already configured beta6
checkout, the rebuild command is simply `make -C src -j4 zclassicd`.

To build and run the upstream test executable containing the added cases:

```bash
make -C src -j4 zcash-gtest &&
./src/zcash-gtest --gtest_filter='CheckBlock.Diagnostic*'
```

The stock gtest launcher initializes proof parameters even for filtered tests;
its existing parameter files must be available. The new cases themselves need
no proofs or wallet data. Their synthetic headers use the same explicit
PoW/Merkle test arguments as existing CheckBlock tests.

## Development verification and limits

- Modified `src/main.cpp` and `src/gtest/test_checkblock.cpp` compile with GCC 14
  against the host C/C++ dependencies. C++14 was selected for the installed
  GoogleTest 1.14 headers; beta6's pinned GoogleTest 1.8 supports its normal C++11
  build. The modified production `main.cpp` also compiles separately in C++11
  mode. No source-language or build-system change is part of this patch.
- Three checked-in regression cases pass in an isolated executable using
  verbatim extracted beta6 `CheckBlock`, `CheckBlockHeader`, `CheckTransaction`,
  and structural transaction-validation bodies. It uses real transaction/block
  types, hashing, serialization, proof-context setup, and validation state.
  Unexercised proof/PoW/chain-parameter boundaries abort if reached, and time is
  fixed. This is focused diagnostic coverage, not a full consensus or proof test.
  All three cases fail against the unmodified beta6 bodies because the required
  diagnostic is absent, then pass with the patch.
- A separate isolated helper/loop harness passes exact-field formatting,
  `INT64_MIN` and maximum `size_t`, unchanged valid/invalid/error states,
  accumulated DoS 107, literal percent signs in reject reasons, indices 0/1/2,
  first-failure exit, and no failure log on success. Its transaction checker is
  a test double.
- That harness passes Clang 20 ASan/UBSan/LSan and Valgrind: zero errors and
  zero leaks. LSan was run outside the ptrace-based development sandbox.
- `git diff --check` passes. A focused pmccabe gate passes: new production helper
  M=1, changed `CheckBlock` M=15, added named test helpers M<=2. The legacy file
  has unrelated functions above this limit; no global lint pass is claimed.
- Full `zclassicd` and `test/test_bitcoin` builds reach the linker and fail with
  `cannot find -lrustzcash`. The original dependency is absent here. No diagnostic
  daemon binary or full upstream test-suite pass is claimed. No Rust toolchain
  was installed, and no node or mining process was started.

Next step: build with the existing beta6 dependency prefix on Hetzner, collect
the new rejection line for the reported block, and use its transaction identity
and reject reason to guide further investigation without changing consensus.
