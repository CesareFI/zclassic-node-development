#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic evidence string regression and observer-cost benchmark. No node runs.
# Usage: bash tools/scripts/evidence_sources_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C

bench=0
case "${1:-}" in
    --bench) bench=1; shift ;;
    --selftest) shift ;;
esac
script_dir="$(cd "$(dirname "$0")" && pwd)"
library="${1:-$script_dir/lib/evidence_sources.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-evidence-strings.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
unset ZCL_EVIDENCE_SOURCES_SH_LOADED
# shellcheck source=tools/scripts/lib/evidence_sources.sh
. "$library"

check() {
    local label="$1" input="$2" expected="$3"
    evidence_json_escape "$input" > "$fixture/actual"
    printf '%s' "$expected" > "$fixture/expected"
    cmp "$fixture/expected" "$fixture/actual"
    evidence_jstr "$input" > "$fixture/actual"
    printf '"%s"' "$expected" > "$fixture/expected"
    cmp "$fixture/expected" "$fixture/actual"
    printf '  ok: %s\n' "$label"
}

check empty '' ''
check identifier 'waiting_for_headers' 'waiting_for_headers'
check quotes '"a"' '\"a\"'
check backslashes 'a\b\\c\' 'a\\b\\\\c\\'
check mixed $'\\"\n\r\t&%s*[]?' '\\\"   &%s*[]?'
check whitespace $'\n\ta\r\nb\t\n' '  a  b  '
check utf8 'café → tip' 'café → tip'
evidence_json_escape > "$fixture/actual"
test ! -s "$fixture/actual"
test "$(evidence_jstr)" = '""'

# Differential byte coverage against the previous streaming implementation.
# NUL cannot be represented in a Bash argument. Other control bytes retain
# their existing behavior; this change does not broaden the escaping contract.
bytes=''
for ((i=1; i<=255; i++)); do
    printf -v octal '%03o' "$i"
    printf -v byte '%b' "\\$octal"
    bytes+="$byte"
done
for input in "$bytes" "$bytes$bytes$bytes$bytes"; do
    printf '%s' "$input" | tr '\n\r\t' '   ' |
        sed 's/\\/\\\\/g; s/"/\\"/g' > "$fixture/expected"
    evidence_json_escape "$input" > "$fixture/actual"
    cmp "$fixture/expected" "$fixture/actual"
done
echo '  ok: all non-NUL byte values, repeated mixed input, exact output bytes'

# A deterministic observer-cost gate, independent of CPU load and caches.
: > "$fixture/tools"
(
    tr() { echo tr >> "$fixture/tools"; command tr "$@"; }
    sed() { echo sed >> "$fixture/tools"; command sed "$@"; }
    evidence_jstr $'waiting_for_headers\n"fixture"\\path' > /dev/null
)
tool_count="$(wc -l < "$fixture/tools")"
printf 'external text tools per string: %s (baseline: 2)\n' "$tool_count"

if [ "$bench" = 1 ]; then
    bench_input=$'waiting_for_headers\n"fixture"\\path\t123456'
    printf 'benchmark: 500 evidence_jstr calls, fixed %s-byte input, warm host caches\n' "${#bench_input}"
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time (
        for ((i=0; i<500; i++)); do
            evidence_jstr "$bench_input" > /dev/null
        done
    )
fi
if [ "$tool_count" -ne 0 ]; then
    echo 'selftest: FAIL string emission still starts external text tools' >&2
    exit 1
fi
echo 'selftest: PASS evidence strings'
