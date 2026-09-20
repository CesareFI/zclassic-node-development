#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exact-byte regression and optional benchmark for stopwatch string emission.
# Usage: bash tools/scripts/stopwatch_string_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C

bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
library="${1:-$script_dir/stopwatch_json_lib.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-stopwatch-strings.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# shellcheck source=tools/scripts/stopwatch_json_lib.sh
. "$library"

check() {
    local label="$1" input="$2" expected="$3"
    json_escape "$input" > "$fixture/actual"
    printf '%s' "$expected" > "$fixture/expected"
    cmp "$fixture/expected" "$fixture/actual"
    json_string "$input" > "$fixture/actual"
    printf '"%s"' "$expected" > "$fixture/expected"
    cmp "$fixture/expected" "$fixture/actual"
    printf '  ok: %s\n' "$label"
}

check empty '' ''
check phase 'waiting_for_headers' 'waiting_for_headers'
check quotes '"a"' '\"a\"'
check backslashes 'a\b\\c\' 'a\\b\\\\c\\'
check mixed $'\\"\n\r\t&%s*[]?' '\\\" \r\t&%s*[]?'
check whitespace $'\n\ta\r\nb\t\n\n' ' \ta\r b\t  '
check literal-escapes '\t\r\n' '\\t\\r\\n'
check utf8 'café → tip' 'café → tip'

# The streaming implementation is the compatibility oracle. NUL cannot be
# carried in Bash arguments; other controls keep their existing behavior.
# This optimization does not broaden the helper's JSON escaping contract.
bytes=''
for ((i=1; i<=255; i++)); do
    printf -v octal '%03o' "$i"
    printf -v byte '%b' "\\$octal"
    bytes+="$byte"
done
for input in "$bytes" "$bytes$bytes$bytes$bytes"; do
    printf '%s' "$input" |
        sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g' |
        tr '\n' ' ' > "$fixture/expected"
    json_escape "$input" > "$fixture/actual"
    cmp "$fixture/expected" "$fixture/actual"
done
echo '  ok: every non-NUL byte, repeated mixed input, exact output bytes'

# Count the baseline tools even inside json_string's command substitution.
# Timing is informative; this structural cost bound is the regression gate.
: > "$fixture/tools"
(
    sed() { echo sed >> "$fixture/tools"; command sed "$@"; }
    tr() { echo tr >> "$fixture/tools"; command tr "$@"; }
    json_string $'waiting_for_headers\n"fixture"\\path\t123456' > /dev/null
)
tool_count="$(wc -l < "$fixture/tools")"
printf 'external text tools per string: %s (baseline: 2)\n' "$tool_count"

if (( bench )); then
    bench_input=$'waiting_for_headers\n"fixture"\\path\t123456'
    printf 'benchmark: 500 captured json_string calls, %s-byte input, warm host caches\n' "${#bench_input}"
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time (
        for ((i=0; i<500; i++)); do
            value="$(json_string "$bench_input")"
            [[ -n $value ]]
        done
    )
fi
if [[ $tool_count -ne 0 ]]; then
    echo 'selftest: FAIL string emission still starts external text tools' >&2
    exit 1
fi
# Catch replacement with a different external tool as well.
(
    PATH=/nonexistent
    actual="$(json_string $'\\"\n\r\t')"
    [[ $actual == '"\\\" \r\t"' ]]
)
echo 'selftest: PASS stopwatch strings'
