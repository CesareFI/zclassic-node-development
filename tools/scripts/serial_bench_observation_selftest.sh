#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic CLI regression: incomplete parses must never become throughput.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bin="${1:-$root/build/bin/serial_bench}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/serial-bench-observation.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() { printf 'serial-bench-observation: FAIL: %s\n' "$*" >&2; exit 1; }

# Serialization fixture only, not a consensus-valid block: a zeroed header,
# empty solution and one v1 transaction with empty inputs/outputs.
printf '%0280d000101000000000000000000\n' 0 > "$tmp/complete.hex"
printf '00\n' > "$tmp/header-short.hex"
# Enough bytes to allocate the transaction array, then an incomplete input.
printf '%0280d000101000000010000000000\n' 0 > "$tmp/transaction-short.hex"
sed 's/$/00/' "$tmp/complete.hex" > "$tmp/trailing.hex"
cat "$tmp/complete.hex" "$tmp/header-short.hex" > "$tmp/mixed.hex"

for fixture in header-short transaction-short trailing mixed; do
    rc=0
    "$bin" --corpus="$tmp/$fixture.hex" --reps=3 --csv \
        > "$tmp/out" 2> "$tmp/err" || rc=$?
    [ "$rc" -eq 2 ] || fail "$fixture exited $rc, expected observation refusal (2)"
    [ ! -s "$tmp/out" ] || fail "$fixture published CSV measurements"
    grep -q 'serial_bench: incomplete block parse at corpus entry' "$tmp/err" ||
        fail "$fixture omitted the parse diagnostic"
done
grep -q 'corpus entry 2' "$tmp/err" || fail 'mixed corpus did not identify its rejected entry'

"$bin" --corpus="$tmp/complete.hex" --reps=3 --csv > "$tmp/out"
[ "$(wc -l < "$tmp/out")" -eq 4 ] || fail 'complete fixture lost variant rows'
[ "$(grep -c ',1$' "$tmp/out")" -eq 3 ] || fail 'complete fixture lost parity verification'
"$bin" --reps=3 --self-test > "$tmp/out"
grep -q 'parity checker rejects a 1-bit difference: YES' "$tmp/out" || fail 'parity control failed'
grep -q 'throughput (shipped):' "$tmp/out" || fail 'synthetic control lost throughput'
printf 'serial-bench-observation: PASS (4 refusals, complete and synthetic controls)\n'
bash "$root/tools/scripts/serial_bench_corpus_selftest.sh" "$bin"
