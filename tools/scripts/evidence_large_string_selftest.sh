#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Byte equivalence and bounded Bash replacement work for large evidence fields.
# Usage: bash tools/scripts/evidence_large_string_selftest.sh [--bench] [--baseline] [library]
set -euo pipefail
export LC_ALL=${LC_ALL:-C}
bench=0
baseline=0
while [[ ${1:-} == --* ]]; do
    case $1 in
        --bench) bench=1 ;;
        --baseline) baseline=1 ;;
        --selftest) ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
library=${1:-$root/tools/scripts/lib/evidence_sources.sh}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-evidence-large.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
unset ZCL_EVIDENCE_SOURCES_SH_LOADED
# shellcheck source=tools/scripts/lib/evidence_sources.sh
. "$library"

check() {
    local input=$1 expected_tools=0
    # The legacy transformation is the byte oracle. Command substitution
    # also tolerates sed implementations adding a final newline.
    local expected
    expected=$(printf '%s' "$input" | tr '\n\r\t' '   ' |
        sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '"%s"' "$expected" > "$fixture/expected"
    : > "$fixture/tools"
    (
        tr() { echo tr >> "$fixture/tools"; command tr "$@"; }
        sed() { echo sed >> "$fixture/tools"; command sed "$@"; }
        evidence_jstr "$input" > "$fixture/actual"
    )
    cmp "$fixture/expected" "$fixture/actual"
    if (( ${#input} > 4096 && !baseline )); then expected_tools=2; fi
    test "$(wc -l < "$fixture/tools")" -eq "$expected_tools" || {
        echo "FAIL: ${#input}-byte field used wrong serialization path" >&2
        return 1
    }
}

# Cover both sides of the path boundary, ordinary identifiers, dense escapes,
# raw whitespace and every byte Bash arguments can contain (all except NUL).
for size in 4095 4096 4097 32768; do
    printf -v input '%*s' "$size" ''
    check "${input// /x}"
    check "${input// /\"}"
done
bytes=''
for ((i=1; i<=255; i++)); do
    printf -v octal '%03o' "$i"
    printf -v byte '%b' "\\$octal"
    bytes+="$byte"
done
input=$bytes
for ((i=0; i<5; i++)); do input+=$input; done
check "$input"
check "$input"$'\n\r\t\\"'
printf -v input '%5000s' ''
check "${input// /é→}"$'\n\r\t\\"'
printf 'byte equivalence and routing: PASS (4095, 4096, 4097, 32768 bytes; mixed non-NUL bytes)\n'

if (( bench )); then
    printf -v input '%32768s' ''
    input=${input// /\"}
    echo 'benchmark: three 32768-byte quote-only fields, warm host caches'
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    for ((i=0; i<3; i++)); do
        time evidence_jstr "$input" > /dev/null
    done
fi
echo 'selftest: PASS large evidence strings'
