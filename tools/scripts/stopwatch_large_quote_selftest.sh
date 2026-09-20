#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Byte regression and optional observer-cost benchmark; no node or datadir.
# Usage: bash tools/scripts/stopwatch_large_quote_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=${LC_ALL:-C}
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
library=${1:-$root/tools/scripts/stopwatch_json_lib.sh}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-stopwatch-large-quote.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
# shellcheck source=tools/scripts/stopwatch_json_lib.sh
. "$library"

check() {
    local input=$1
    # The original streaming transformation is the independent byte oracle.
    {
        printf '"'
        printf '%s' "$input" |
            sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g' |
            tr '\n' ' '
        printf '"'
    } > "$fixture/expected"
    json_string "$input" > "$fixture/actual"
    cmp "$fixture/expected" "$fixture/actual"
}

# Exercise both sides of the size boundary and dense, sparse, and absent
# escapes. Preserve trailing whitespace, arbitrary non-NUL bytes, and UTF-8.
for size in 4095 4096 4097 32768; do
    printf -v input '%*s' "$size" ''
    check "${input// /x}"
    check "${input// /\"}"
    check "$input"$'\\"\t\r\n\n'
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
check "$input"$'\n\n'
printf -v input '%5000s' ''
check "${input// /é→}"$'\t\r\n'

# Small frequent fields must still work without external executables.
(
    PATH=/nonexistent
    json_string $'short "reason"\n' > "$fixture/short"
)
printf '"short \\"reason\\" "' > "$fixture/expected"
cmp "$fixture/expected" "$fixture/short"
# A failed streaming encoder must not appear to produce a successful field.
(
    sed() { command cat > /dev/null; return 17; }
    rc=0
    json_string "$input" > "$fixture/failed" || rc=$?
    [[ $rc -eq 17 ]] || { echo 'FAIL: encoder failure hidden' >&2; exit 1; }
)
echo 'PASS: large stopwatch quoting (15 byte cases, short field, encoder failure)'

if (( bench )); then
    printf -v input '%32768s' ''
    input=${input// /\"}
    echo 'benchmark: three 32768-byte quote fields, warm host caches'
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    for trial in 1 2 3; do
        time json_string "$input" > /dev/null
    done
fi
