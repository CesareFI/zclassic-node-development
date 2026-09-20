#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the copy-import height observer without launching a node.
# Usage: sh tools/scripts/import_copy_tip_selftest.sh [--bench] [HARNESS]
set -eu
export LC_ALL=C
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
[ "$#" -le 1 ] || { echo 'import-copy-tip: too many arguments' >&2; exit 2; }
script="${1:-$SCRIPT_DIR/import-copy-prove.sh}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zcl-import-tip.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

# Extract only the real observer; sourcing the harness would copy a datadir.
sed -n '/^tip() {/,/^}/p' "$script" > "$tmp/reader.sh"
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
        printf 'import-copy-tip: FAIL %s: got <%s>, expected <%s>\n' "$1" "$got" "$3" >&2
        exit 1
    }
    checks=$((checks + 1))
}
check result '{"result":42,"error":null}' 42
check zero '{"result":0}' 0
check negative '{"result":-1}' -1
check wide '{"result":18446744073709551615}' 18446744073709551615
check leading-zero '{"result":00042}' 00042
check whitespace '{"result" 	: 	42}' 42
check duplicate '{"result":42,"result":73}' 73
check lines '{"result":42}
{"result":73}' 42
check later-line 'noise
{"result":42}' 42
check prefix '{"result_next":73,"result":42}' 42
check missing '{}' ''
check empty '' ''
check null '{"result":null}' ''
check quoted '{"result":"42"}' ''
check bare 42 ''
check first-integer '{"result":null,"result":42}' 42
check last-integer '{"result":42,"result":null}' 42
check null-line '{"result":null}
{"result":73}' 73
# Pin the existing flat-field extraction policy, not general JSON validation.
check integer-prefix '{"result":42.5}' 42
check split-field '{"result"
:42}' ''
[ "$(wc -l < "$tmp/rpc.calls")" -eq "$checks" ]
printf 'import-copy-tip: PASS (%s cases; one RPC per read)\n' "$checks"

if [ "$bench" -eq 1 ]; then
    i=0
    while [ "$i" -lt 300 ]; do
        fixture='{"result":42,"error":null}'; tip >/dev/null
        i=$((i + 1))
    done
    echo 'import-copy-tip: benchmark completed 300 reads'
fi

# Deterministic performance gate; wall time is informational under host load.
sed() { printf 'sed\n' >> "$tmp/parsers"; command sed "$@"; }
head() { printf 'head\n' >> "$tmp/parsers"; command head "$@"; }
: > "$tmp/parsers"
fixture='{"result":42}'; tip >/dev/null
fixture='{"result":null}'; tip >/dev/null
fixture='{"result":-1}'; tip >/dev/null
count="$(wc -l < "$tmp/parsers")"
printf 'import-copy-tip: parser processes for three reads=%s (maximum 3)\n' "$count"
[ "$count" -le 3 ]
