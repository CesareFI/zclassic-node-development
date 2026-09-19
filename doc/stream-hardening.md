# Stream bounds hardening

## In-memory reads (2026-09-19)

`CBaseDataStream::read` previously added a `size_t` request length to its
cursor and narrowed the result to `unsigned int` before checking the buffer
boundary. With one byte already consumed from a two-byte stream, a request
for `SIZE_MAX` bytes wrapped to zero and reached `memcpy`. A standalone build
using the production header reproduced AddressSanitizer's
`negative-size-param` failure at that copy. This demonstrates an unsafe stream
API call; it does not establish a remotely reachable network exploit.

The cursor now uses the backing vector's size type. Reads and skips compare
their requested length with the remaining bytes before calculating the next
position. An oversized request throws without changing the stream or copying
data. Zero-length operations, exact consumption, reuse, negative-skip rejection,
and the serialized representation retain their existing behavior.

`serialize_tests/datastream_read_bounds` and
`serialize_tests/datastream_ignore_bounds` cover ordinary overreads, `SIZE_MAX`,
the 32-bit truncation boundary on wider hosts, failure-state preservation,
null pointers, exact consumption, and stream reuse. The two test bodies also
passed as a standalone ASan/UBSan executable (37 assertions). GCC's analyzer
reported no finding for the focused reproducer; extra conversion warnings
remain in the separate file-buffer implementation and existing dependencies.

This changes buffer safety only. Transaction and block validity predicates,
proof verification, chain selection, activation parameters, and consensus
serialization formats are unchanged.

The daemon and both test executables were rebuilt using the existing native
build's dependency path and C++14 mode required by the host GoogleTest headers:

```sh
make -C src -j6 zclassicd test/test_bitcoin zcash-gtest \
  LDFLAGS=-L/tmp/zclassic-ibd-rust/lib CXX='g++ -std=c++14'
src/test/test_bitcoin --run_test=serialize_tests --report_level=detailed
src/zcash-gtest
```

All 14 serialization cases passed (202,388 assertions), as did all 177 enabled
GoogleTests. A 640-block loopback replay reached the expected hash
`0000004cfd343b54fdce55d0af6932b6f8c0afa35c5b7bf41c491d455d50e674`,
with exactly 640 block requests, 640 headers sent, and five header requests.
This is a compatibility check, not a performance claim.
The full Boost suite also passed: 376 cases and 142,446,319 assertions.
`git diff --check` passed. Compiler warnings were reviewed; none originated in
the changed read/skip implementation or the new test cases.

## In-memory capacity requests (2026-09-19)

The follow-up review reproduced a related failure in `resize` and `reserve`.
After consuming one byte, requesting `SIZE_MAX` remaining bytes wrapped the
underlying vector size to zero. `reserve` silently succeeded, and `resize`
shrunk the backing vector while leaving the cursor beyond its end. The stream
then reported `SIZE_MAX` remaining bytes. The regression failed before the fix
without requiring a large allocation.

Both methods now check the request against `vch.max_size() - nReadPos` before
adding the cursor. Invalid requests throw `std::length_error` while preserving
the unread bytes. The new regression also checks ordinary reservation, growth,
shrinking, zero remaining length, and rewind behavior. All three stream test
bodies passed in a C++11 ASan/UBSan executable (48 assertions); the focused GCC
analyzer check completed without diagnostics.

These checks change neither serialized bytes nor any transaction or block
validity rule. They reject impossible storage requests at the buffer boundary.

The rebuilt daemon passed another 640-block replay with the same expected tip,
640 block requests, 640 headers sent, and five header requests. All 15
serialization cases passed (202,399 assertions), as did 107 broader Boost cases
covering allocation, address management, networking, DoS handling, bootstrap
protocols, validation, coins, and database wrappers (47,320,609 assertions).
All 177 enabled GoogleTests passed. Compiler warnings were reviewed and
`git diff --check` passed. The full Boost suite result above belongs to the
preceding read-bound change; this follow-up used the stated relevant suites.
