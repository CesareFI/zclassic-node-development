#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# A damaged record must not silently remove work from an IBD parser benchmark.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bin="${1:-$root/build/bin/serial_bench}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/serial-bench-partial.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
fail() { printf 'serial-bench-partial: FAIL: %s\n' "$*" >&2; exit 1; }

# Serialization fixture only; this is not a consensus-valid block.
printf '%0280d000101000000000000000000\n' 0 > "$tmp/valid.hex"
checks=0
for bad in zz 0 000 '00 0'; do
    for position in first middle last; do
        case "$position" in
            first) printf '%s\n' "$bad"; cat "$tmp/valid.hex" ;;
            middle) cat "$tmp/valid.hex"; printf '%s\n' "$bad"; cat "$tmp/valid.hex" ;;
            last) cat "$tmp/valid.hex"; printf '%s\n' "$bad" ;;
        esac > "$tmp/mixed.hex"
        for mode in text csv; do
            args=()
            [[ $mode != csv ]] || args+=(--csv)
            rc=0
            "$bin" --corpus="$tmp/mixed.hex" --reps=3 "${args[@]}" \
                > "$tmp/out" 2> "$tmp/err" || rc=$?
            [[ $rc == 1 ]] || fail "$bad/$position/$mode: exit=$rc, expected 1"
            [[ ! -s $tmp/out ]] || fail "$bad/$position/$mode: published measurements"
            grep -q 'refusing a partial workload' "$tmp/err" || fail 'missing diagnostic'
            checks=$((checks + 1))
        done
    done
done

# Empty lines, CRLF, and a final record without newline remain supported.
{
    printf '\n\r\n'
    sed 's/$/\r/' "$tmp/valid.hex"
    tr -d '\n' < "$tmp/valid.hex"
} > "$tmp/complete.hex"
"$bin" --corpus="$tmp/complete.hex" --reps=3 > "$tmp/out"
grep -q 'blocks=2 ' "$tmp/out" || fail 'complete records were lost'
"$bin" --corpus="$tmp/complete.hex" --reps=3 --csv > "$tmp/out"
[[ $(wc -l < "$tmp/out") == 4 ]] || fail 'missing CSV variants'
[[ $(grep -c ',1$' "$tmp/out") == 3 ]] || fail 'lost parity verification'
printf 'serial-bench-partial: PASS (%s refusals, text and CSV positive controls)\n' "$checks"
