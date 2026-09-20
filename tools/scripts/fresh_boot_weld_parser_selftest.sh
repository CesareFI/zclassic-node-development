#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Test only the cold-boot proof's integer reader; never source its live driver.
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script="${1:-$SCRIPT_DIR/fresh-boot-weld-prove.sh}"
[ "$#" -le 1 ] || { echo 'usage: fresh_boot_weld_parser_selftest.sh [--bench] [SCRIPT]' >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zcl-weld-parser.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
sed -n '/^jget() {/,/^}/p' "$script" > "$tmp/reader.sh"
. "$tmp/reader.sh"
declare -F jget >/dev/null
checks=0
check() {
    local got rc test_shell
    printf '%s' "$2" > "$tmp/input"
    for test_shell in sh bash; do
        rc=0
        # Match the driver's no-pipefail status semantics, including large
        # replies. A file avoids the OS per-argument size limit for fixtures.
        got="$("$test_shell" -c '. "$1"; jget "$(cat "$2")" "$3"' \
            _ "$tmp/reader.sh" "$tmp/input" "${5:-hstar}")" || rc=$?
        if [ "$got" != "$3" ] || [ "$rc" -ne "$4" ]; then
            printf 'weld-parser: FAIL %s (%s): value=<%s> rc=%s\n' \
                "$1" "$test_shell" "$got" "$rc" >&2
            exit 1
        fi
        checks=$((checks + 1))
    done
}
check compact '{"hstar":3056758}' 3056758 0
check zero '{"hstar":0}' 0 0
check negative '{"hstar":-1}' -1 0
check missing '{}' '' 1
check empty '' '' 1
check exact-key '{"hstar_next_height":8,"hstar":42}' 42 0
check duplicate '{"hstar":42,"hstar":99}' 42 0
check first-integer '{"hstar":null,"hstar":"7","hstar":42}' 42 0
check wide '{"hstar":18446744073709551615}' 18446744073709551615 0
check leading-zeros '{"hstar":00042}' 00042 0
check integer-prefix '{"hstar":42.5}' 42 0
check multiline $'{\n"hstar" \t: 42,\n"hstar":99}' 42 0
check split-field $'{"hstar"\n:42}' '' 1
check whitespace $'{"hstar"\r\v\f:\t42}' 42 0
check alternate-key '{"hstar":42,"network_tip":99}' 99 0 network_tip
check wrong-separator '{"hstar"=7,"hstar":42}' 42 0
check dangling-minus '{"hstar":-,"hstar":42}' 42 0
check double-minus '{"hstar":--7}' '' 1
check separated-sign '{"hstar":- 7}' '' 1
check negative-zero '{"hstar":-000}' -000 0
check backslash-literal '{"hstar":\t7,"hstar":42}' 42 0
printf -v padding '%262144s' ''
check large "{\"hstar\":42,\"padding\":\"$padding\",\"hstar\":99}" 42 0
printf 'weld-parser: PASS (%s value/status checks)\n' "$checks"

if [ "$bench" -eq 1 ]; then
    TIMEFORMAT='weld-parser: 1000 sample extractions wall=%3R user=%3U sys=%3S'
    time for ((i=0; i<1000; i++)); do
        value="$(jget '{"hstar":3056758,"network_tip":3200000,"coins_applied_height":3056758}' hstar)"
        [ "$value" = 3056758 ]
    done
fi

# Deterministic observer-cost regression: no parsers per sample, including a
# missing field. A time threshold would grade host load rather than the change.
awk() { printf 'awk\n' >> "$tmp/parsers"; command awk "$@"; }
grep() { printf 'grep\n' >> "$tmp/parsers"; command grep "$@"; }
head() { printf 'head\n' >> "$tmp/parsers"; command head "$@"; }
: > "$tmp/parsers"
jget '{"hstar":42}' hstar >/dev/null
if jget '{}' hstar >/dev/null; then
    echo 'weld-parser: FAIL missing field succeeded' >&2
    exit 1
fi
count="$(wc -l < "$tmp/parsers")"
printf 'weld-parser: parser invocations for two samples=%s (required 0)\n' "$count"
[ "$count" -eq 0 ]
value="$(PATH=/nonexistent jget '{"hstar":42}' hstar)"
[ "$value" = 42 ]
