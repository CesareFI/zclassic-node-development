#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# An explicitly requested corpus must never be replaced by synthetic work.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bin="${1:-$root/build/bin/serial_bench}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/serial-bench-corpus.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
fail() { printf 'serial-bench-corpus: FAIL: %s\n' "$*" >&2; exit 1; }

: > "$tmp/empty.hex"
printf 'not hex\n' > "$tmp/invalid.hex"
printf '\n\r\n' > "$tmp/blank.hex"
mkdir "$tmp/directory"

for fixture in missing.hex empty.hex invalid.hex blank.hex directory ''; do
    path="$tmp/$fixture"
    [ -n "$fixture" ] || path=''
    for mode in text csv; do
        args=()
        [ "$mode" != csv ] || args+=(--csv)
        rc=0
        "$bin" --corpus="$path" --reps=3 "${args[@]}" \
            > "$tmp/out" 2> "$tmp/err" || rc=$?
        [ "$rc" -eq 1 ] || fail "$fixture ($mode): exit=$rc, expected 1"
        [ ! -s "$tmp/out" ] || fail "$fixture ($mode): published measurements"
        grep -q 'serial_bench: could not load requested corpus' "$tmp/err" ||
            fail "$fixture ($mode): omitted corpus diagnostic"
    done
done

# Positive control: serialization fixture only, not a consensus-valid block.
printf '%0280d000101000000000000000000\n' 0 > "$tmp/complete.hex"
"$bin" --corpus="$tmp/complete.hex" --reps=3 --csv > "$tmp/out"
[ "$(wc -l < "$tmp/out")" -eq 4 ] || fail 'complete corpus lost CSV rows'
[ "$(grep -c ',1$' "$tmp/out")" -eq 3 ] || fail 'complete corpus lost parity'
"$bin" --reps=3 > "$tmp/out"
grep -q 'SYNTHETIC (not representative of the chain)' "$tmp/out" ||
    fail 'omitted corpus lost its explicitly labelled synthetic control'
"$bin" --reps=3 --csv > "$tmp/out"
[ "$(wc -l < "$tmp/out")" -eq 4 ] || fail 'omitted corpus lost CSV control'
printf 'serial-bench-corpus: PASS (12 refusals, explicit and omitted controls)\n'
