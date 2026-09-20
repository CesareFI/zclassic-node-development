#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Test only the instant-on proof's height parser; never launch/copy a node.
# Usage: sh tools/scripts/instant_on_tip_selftest.sh [--bench] [HARNESS]
set -eu
export LC_ALL=C
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
[ "$#" -le 1 ] || { echo 'instant-on-tip: too many arguments' >&2; exit 2; }
subject=${1:-$SCRIPT_DIR/instant-on-copy-prove.sh}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/zcl-instant-tip.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Sourcing the full harness would execute its node/datadir machinery.
sed -n '/^parse_tip() {/,/^}/p' "$subject" > "$tmp/parser.sh"
[ -s "$tmp/parser.sh" ]
. "$tmp/parser.sh"
checks=0
check() {
    parse_tip "$2" > "$tmp/actual"
    if [ -n "$3" ]; then printf '%s\n' "$3"; fi > "$tmp/expected"
    if ! cmp -s "$tmp/actual" "$tmp/expected"; then
        printf 'instant-on-tip: FAIL %s\n' "$1" >&2
        exit 1
    fi
    checks=$((checks + 1))
}
check bare 42 42
check zero 0 0
check negative -1 -1
check wide 18446744073709551615 18446744073709551615
check leading-zero 00042 00042
check whitespace ' 	42 	' 42
check multiline 'noise
42
73' 42
check quoted '"42"' ''
check fraction 42.5 ''
check suffix '42 trailing' ''
check empty '' ''
check object '{}' ''
check result '{"result":42,"error":null}' 42
check result-negative '{"result":-1}' -1
check result-wide '{"result":18446744073709551615}' 18446744073709551615
check result-leading-zero '{"result":00042}' 00042
check duplicate '{"result":42,"result":73}' 73
check result-whitespace '{"result" 	: 	42}' 42
check result-lines '{"result":42}
{"result":73}' 42
check similar-key '{"result_next":73,"result":42}' 42
check null '{"result":null}' ''
check string '{"result":"42"}' ''
check first-integer '{"result":null,"result":42}' 42
check last-integer '{"result":42,"result":null}' 42
# Preserve the existing scalar extraction grammar; this is not JSON validation.
check integer-prefix '{"result":42.5}' 42
check split-field '{"result"
:42}' ''
check envelope-precedence '42
{"result":73}' 73
check envelope-no-fallback '42
{"result":null}' ''
check result-later '{"result":null}
{"result":73}' 73
printf 'instant-on-tip: PASS (%s output/status cases)\n' "$checks"

if [ "$bench" -eq 1 ]; then
    i=0
    while [ "$i" -lt 200 ]; do
        parse_tip 42 >/dev/null
        parse_tip '{"result":42,"error":null}' >/dev/null
        parse_tip '{"result":null}' >/dev/null
        i=$((i + 1))
    done
    echo 'instant-on-tip: benchmark completed 600 reads'
fi

# Count external parser launches even inside pipelines/subshells. Keep timing
# above free of these counter writes; no timing threshold gates shared hosts.
sed() { printf 'sed\n' >> "$tmp/parsers"; command sed "$@"; }
head() { printf 'head\n' >> "$tmp/parsers"; command head "$@"; }
: > "$tmp/parsers"
parse_tip 42 >/dev/null
parse_tip '{"result":42}' >/dev/null
parse_tip '{"result":null}' >/dev/null
count=$(wc -l < "$tmp/parsers")
printf 'instant-on-tip: parser launches for three reads=%s (required 3)\n' "$count"
[ "$count" -eq 3 ]
