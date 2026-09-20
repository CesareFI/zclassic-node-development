#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise only the copy profiler's height reader: no node or datadir access.
# Usage: sh tools/scripts/repro_copy_tip_selftest.sh [--bench] [HARNESS]
# --bench adds 300 reads; use time to compare a saved baseline with this tree.
set -eu
export LC_ALL=C
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
[ "$#" -le 1 ] || { echo 'repro-copy-tip: too many arguments' >&2; exit 2; }
script="${1:-$SCRIPT_DIR/../repro_on_copy.sh}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zcl-copy-tip.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

# Never source the harness entry point (which would copy and launch a node).
sed -n '/^tip()  {/,/^}/p' "$script" > "$tmp/reader.sh"
test -s "$tmp/reader.sh"
. "$tmp/reader.sh"
rpc() {
    [ "$#" -eq 1 ] && [ "$1" = getblockcount ] || return 1
    printf 'getblockcount\n' >> "$tmp/rpc.calls"
    printf '%s\n' "$fixture"
}
checks=0
check() {
    fixture="$2"
    got="$(tip)"
    [ "$got" = "$3" ] || {
        printf 'repro-copy-tip: FAIL %s: got <%s>, expected <%s>\n' "$1" "$got" "$3" >&2
        exit 1
    }
    checks=$((checks + 1))
}
check plain 42 42
check zero 0 0
check negative -1 -1
check plain-wide 18446744073709551615 18446744073709551615
check plain-leading-zero 00042 00042
check whitespace ' 	42 	' 42
check raw-multiline 'noise
42
73' 42
check raw-string '"42"' ''
check raw-fraction '42.5' ''
check raw-junk '42 trailing' ''
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
check result-prefix '{"result_next":73,"result":42}' 42
check null '{"result":null}' ''
check string '{"result":"42"}' ''
check first-integer '{"result":null,"result":42}' 42
check last-integer '{"result":42,"result":null}' 42
# These are the existing reader's policies, not general JSON validation.
check integer-prefix '{"result":42.5}' 42
check split-field '{"result"
:42}' ''
check envelope-precedence '42
{"result":73}' 73
check envelope-no-fallback '42
{"result":null}' ''
check result-later '{"result":null}
{"result":73}' 73
[ "$(wc -l < "$tmp/rpc.calls")" -eq "$checks" ]
printf 'repro-copy-tip: PASS (%s cases; one RPC per read)\n' "$checks"

if [ "$bench" -eq 1 ]; then
    i=0
    while [ "$i" -lt 100 ]; do
        fixture=42; tip >/dev/null
        fixture='{"result":42,"error":null}'; tip >/dev/null
        fixture='{"result":null}'; tip >/dev/null
        i=$((i + 1))
    done
    echo 'repro-copy-tip: benchmark completed 300 reads'
fi

# Count external parsers, including those inside command substitutions.
sed() { printf 'sed\n' >> "$tmp/parsers"; command sed "$@"; }
head() { printf 'head\n' >> "$tmp/parsers"; command head "$@"; }
awk() { printf 'awk\n' >> "$tmp/parsers"; command awk "$@"; }
: > "$tmp/parsers"
fixture=42; tip >/dev/null
fixture='{"result":42}'; tip >/dev/null
fixture='{"result":null}'; tip >/dev/null
count="$(wc -l < "$tmp/parsers")"
printf 'repro-copy-tip: parser processes for three reads=%s (maximum 3)\n' "$count"
[ "$count" -le 3 ]
