#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Shared sync-observer readers: value/status regression and optional benchmark.
# Usage: bash tools/scripts/evidence_json_readers_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C
bench=0
case ${1:-} in
    --bench) bench=1; shift ;;
    --selftest) shift ;;
esac
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
library=${1:-$script_dir/lib/evidence_sources.sh}
fixture=$(mktemp -d /tmp/z23-evidence-readers.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
unset ZCL_EVIDENCE_SOURCES_SH_LOADED
# shellcheck source=tools/scripts/lib/evidence_sources.sh
. "$library"
fail=0
check() {
    local reader=$1 input=$2 expected=$3 label=$4 rc=0 actual
    "$reader" "$input" value > "$fixture/actual" 2> "$fixture/error" || rc=$?
    # Callers consume these readers through command substitution.
    actual=$(< "$fixture/actual")
    if [[ $rc != 0 || $actual != "${expected%$'\n'}" ]]; then
        printf 'FAIL: %s %s (rc=%s)\n' "$reader" "$label" "$rc" >&2
        fail=1
    fi
}
for reader in evidence_json_int evidence_json_str evidence_json_bool; do
    check "$reader" '' '' empty
    check "$reader" '{}' '' absent
    check "$reader" '{"other_value":7,"value_suffix":8}' '' exact-key
    check "$reader" '{"value":null}' '' null
done
check evidence_json_int '{"value":0}' $'0\n' zero
check evidence_json_int $'{"value" \t: -42}' $'-42\n' whitespace-negative
check evidence_json_int '{"value":18446744073709551615}' $'18446744073709551615\n' wide-counter
check evidence_json_int '{"value":0007}' $'0007\n' integer-text
check evidence_json_int '{"value":"7"}' '' quoted-number
check evidence_json_int '{"value":-}' '' bare-minus
check evidence_json_int '{"value":+7}' '' plus-sign
check evidence_json_int '{"value":-0007}' $'-0007\n' negative-integer-text
check evidence_json_int '{"value":1,"value":null}' $'1\n' last-valid-integer
check evidence_json_int $'{"value":\n7}' '' no-cross-line-integer
check evidence_json_int $'{"value"\n:7}' '' no-cross-line-key
check evidence_json_int '{"value":12e3}' $'12\n' existing-exponent-prefix
check evidence_json_str '{"value":""}' $'\n' empty-string
check evidence_json_str $'{"value":""}\n{"value":"later"}' $'\n' first-empty-string
check evidence_json_str '{"value":"waiting for headers"}' $'waiting for headers\n' string
check evidence_json_str '{"value":"a\\b"}' $'a\\\\b\n' literal-backslashes
check evidence_json_bool '{"value":true}' $'true\n' true
check evidence_json_bool $'{"value"\t: false}' $'false\n' false
check evidence_json_bool '{"value":"true"}' '' quoted-boolean

# Preserve the existing compact-field policy, not a general JSON decoder:
# last match on the first matching line, even for integer/boolean prefixes.
check evidence_json_int $'{"value":1,"value":2}\n{"value":3}' $'2\n' duplicates
check evidence_json_str $'{"value":"a","value":"b"}\n{"value":"c"}' $'b\n' duplicates
check evidence_json_bool $'{"value":true,"value":false}\n{"value":true}' $'false\n' duplicates
check evidence_json_int $'unmatched\n{"value":9}\nunmatched' $'9\n' first-matching-line
check evidence_json_int '{"value":12.5}' $'12\n' existing-integer-prefix
check evidence_json_bool '{"value":true_suffix}' $'true\n' existing-boolean-prefix
check evidence_json_str '{"value":"a\"b"}' $'a\\\n' existing-escape-policy

# Enough output to make sed|head fail with SIGPIPE under pipefail. Generate
# in memory; the fixture never talks to a node or reads a production datadir.
for type in int str bool; do
    case $type in
        int) row='{"value":42}'; expected=$'42\n' ;;
        str) row='{"value":"headers"}'; expected=$'headers\n' ;;
        bool) row='{"value":true}'; expected=$'true\n' ;;
    esac
    many="$row"$'\n'
    for ((i=0; i<15; i++)); do many+="$many"; done
    check "evidence_json_$type" "$many" "$expected" large-repeated-response
    check "evidence_json_$type" "${many//value/other}$row" "$expected" late-match
done

# Count both old and new external tools; elapsed time remains informational.
: > "$fixture/tools"
sed() { printf 'sed\n' >> "$fixture/tools"; command sed "$@"; }
head() { printf 'head\n' >> "$fixture/tools"; command head "$@"; }
doc='{"height":3200000,"stage":"header_admit","ready":false}'
evidence_json_int "$doc" height > /dev/null
evidence_json_str "$doc" stage > /dev/null
evidence_json_bool "$doc" ready > /dev/null
calls=$(wc -l < "$fixture/tools")
: > "$fixture/tools"
# Exactly 4096 bytes stays on the compact path; larger input, multiline
# responses and legacy BRE keys must keep the streaming sed interpretation.
printf -v padding '%4085s' ''
evidence_json_int "${padding}{\"value\":7}" value > "$fixture/actual"
printf '7\n' > "$fixture/expected"
cmp "$fixture/expected" "$fixture/actual"
compact_calls=$(wc -l < "$fixture/tools")
: > "$fixture/tools"
evidence_json_int " ${padding}{\"value\":7}" value > /dev/null
evidence_json_int $'{"value":7}\n{"value":8}' value > /dev/null
evidence_json_int '{"value+":7}' 'value+' > "$fixture/actual"
cmp "$fixture/expected" "$fixture/actual"
fallback_calls=$(wc -l < "$fixture/tools")
unset -f sed head
printf 'three field reads: external_tools=%s (baseline: 6)\n' "$calls"
if (( bench )); then
    TIMEFORMAT='500 three-field samples: %3R s wall, %3U s user, %3S s system'
    time for ((i=0; i<500; i++)); do
        evidence_json_int "$doc" height > /dev/null
        evidence_json_str "$doc" stage > /dev/null
        evidence_json_bool "$doc" ready > /dev/null
    done
fi
if [[ $calls != 0 || $compact_calls != 0 || $fallback_calls != 3 ]]; then
    echo 'FAIL: compact fields must avoid tools; large/multiline/regex keys must use fallback' >&2
    fail=1
fi
(( fail == 0 )) || exit 1
echo 'selftest: PASS evidence JSON readers'
