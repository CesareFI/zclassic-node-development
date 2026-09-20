#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic SQL-row decoder regression and process-cost benchmark. No node/RPC.
set -euo pipefail
export LC_ALL=C
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
probe="${1:-$script_dir/tip_agreement_probe.sh}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zcl-tip-rows.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

# Load only the decoder; sourcing the recorder would run operator work.
sed -n '/^sql_rows() {$/,/^}$/p' "$probe" > "$tmp/reader.sh"
. "$tmp/reader.sh"
declare -F sql_rows > /dev/null

reference_rows() {
    sed -n 's/.*"rows":\[\(.*\)\],"row_count".*/\1/p' |
        sed 's/\],\[/\n/g' |
        sed 's/^\[//; s/\]$//' |
        sed 's/","/\x1f/g; s/,"/\x1f/g; s/",/\x1f/g; s/,/\x1f/g; s/"//g' |
        awk 'NF'
}

checks=0
check() {
    local input="$1"
    printf '%s' "$input" > "$tmp/input"
    reference_rows < "$tmp/input" > "$tmp/expected"
    sql_rows < "$tmp/input" > "$tmp/actual"
    cmp "$tmp/expected" "$tmp/actual"
    checks=$((checks + 1))
}

for input in '' '{}' '{"rows":[],"row_count":0}' \
    '{"rows":[[3]],"row_count":1}' \
    '{"rows":[[3200000,"aabb",2],[3199999,"ccdd",3]],"row_count":2}' \
    '{"rows":[["192.0.2.1"],["[2001:db8::1]"],["peer.onion"]],"row_count":3}' \
    '{"rows":[["",null,-1,true,9007199254740993]],"row_count":1}' \
    '{"rows":[["comma,in,scalar","back\\slash"]],"row_count":1}' \
    '{"rows":[["   "],[""],[],["tail"]],"row_count":4}' \
    '{"rows":[[1]],"row_count":1,"next":{"rows":[[2]],"row_count":1}}' \
    '{"rows":[[1]], "row_count":1}' \
    $'{"rows":[["a\tb"],["c\rd"]],"row_count":2}' \
    $'{"rows":[[1]],"row_count":1}\n{"rows":[[2]],"row_count":1}\n'; do
    check "$input"
done

# The final newline is required by the recorder's while-read consumers.
printf '%s' '{"rows":[["first"],["last"]],"row_count":2}' |
    sql_rows > "$tmp/actual"
printf 'first\nlast\n' > "$tmp/expected"
cmp "$tmp/expected" "$tmp/actual"

input='{"rows":['
for ((i=0; i<10000; i++)); do input+="[$i,\"hash$i\",2],"; done
check "${input%,}],\"row_count\":10000}"

rc=0
(printf '%s' '{"rows":[[1]],"row_count":1}'; exit 7) |
    sql_rows > /dev/null || rc=$?
[ "$rc" -eq 7 ]

: > "$tmp/tools"
(
    sed() { echo sed >> "$tmp/tools"; command sed "$@"; }
    awk() { echo awk >> "$tmp/tools"; command awk "$@"; }
    sql_rows <<< '{"rows":[[1]],"row_count":1}' > /dev/null
)
tool_count="$(wc -l < "$tmp/tools")"
printf 'tip-rows: %s differential cases; external parsers per decode=%s\n' "$checks" "$tool_count"

if [ "$bench" = 1 ]; then
    input='{"rows":['
    for ((i=0; i<64; i++)); do input+="[$i,\"hash$i\",2],"; done
    printf '%s' "${input%,}],\"row_count\":64}" > "$tmp/bench"
    for sample in 1 2 3; do
        TIMEFORMAT="sample=$sample wall=%3R user=%3U sys=%3S seconds"
        time (
            for ((i=0; i<300; i++)); do
                sql_rows < "$tmp/bench" > /dev/null
            done
        )
    done
fi
if [ "$tool_count" -gt 2 ]; then
    echo 'tip-rows: FAIL more than two external parsers per decode' >&2
    exit 1
fi
echo 'tip-rows: PASS'
