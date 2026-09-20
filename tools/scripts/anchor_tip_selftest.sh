#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise only the anchor-copy height reader; never launch/copy a node.
# Usage: sh tools/scripts/anchor_tip_selftest.sh [--bench] [HARNESS]
set -eu
export LC_ALL=C
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
[ "$#" -le 1 ] || { echo 'anchor-tip: too many arguments' >&2; exit 2; }
subject="${1:-$SCRIPT_DIR/anchor-snapshot-copy-prove.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-anchor-tip.XXXXXX")"
trap 'rm -rf -- "$fixture"' EXIT

# Extract the real function, without executing the datadir-copy entry point.
sed -n '/^tip() {/,/^}/p' "$subject" > "$fixture/reader.sh"
test -s "$fixture/reader.sh"
. "$fixture/reader.sh"
rpc() {
    [ "$#" -eq 1 ] && [ "$1" = getblockcount ] || return 1
    printf 'rpc\n' >> "$fixture/calls"
    printf '%s\n' "$response"
}
checks=0
check() {
    response="$2"
    got="$(tip)"
    [ "$got" = "$3" ] || {
        printf 'anchor-tip: FAIL %s: got <%s>, expected <%s>\n' "$1" "$got" "$3" >&2
        exit 1
    }
    checks=$((checks + 1))
}
check positive '{"result":42,"error":null}' 42
check zero '{"result":0}' 0
check negative '{"result":-1}' -1
check wide '{"result":18446744073709551615}' 18446744073709551615
check leading-zero '{"result":00042}' 00042
check whitespace '{"result" 	: 	42}' 42
check duplicates '{"result":42,"result":73}' 73
check lines '{"result":42}
{"result":73}' 42
check later 'noise
{"result":42}' 42
check similar-key '{"result_next":73,"result":42}' 42
check null '{"result":null}' ''
check empty '' ''
check missing '{}' ''
check string '{"result":"42"}' ''
check bare 42 ''
check first-integer '{"result":null,"result":42}' 42
check last-integer '{"result":42,"result":null}' 42
check null-then-integer '{"result":null}
{"result":42}' 42
# Pin existing line-local integer-prefix behavior, not general JSON validity.
check fraction '{"result":42.5}' 42
check split-key '{"result"
:42}' ''
check final-line '{"result":null}
{"result":null}
{"result":42}' 42
[ "$(wc -l < "$fixture/calls")" -eq "$checks" ]
printf 'anchor-tip: PASS (%s cases; one RPC per read)\n' "$checks"

if [ "$bench" -eq 1 ]; then
    i=0
    while [ "$i" -lt 100 ]; do
        response='{"result":42}'; tip >/dev/null
        response='{"result":null}'; tip >/dev/null
        response='noise
{"result":42}'; tip >/dev/null
        i=$((i + 1))
    done
    echo 'anchor-tip: benchmark completed 300 reads'
fi

# Record external parser launches even inside command substitutions.
sed() { printf 'sed\n' >> "$fixture/parsers"; command sed "$@"; }
head() { printf 'head\n' >> "$fixture/parsers"; command head "$@"; }
: > "$fixture/parsers"
response='{"result":42}'; tip >/dev/null
response='{"result":null}'; tip >/dev/null
response='noise
{"result":42}'; tip >/dev/null
count="$(wc -l < "$fixture/parsers")"
printf 'anchor-tip: parser launches for three reads=%s (expected 3)\n' "$count"
[ "$count" -eq 3 ]
