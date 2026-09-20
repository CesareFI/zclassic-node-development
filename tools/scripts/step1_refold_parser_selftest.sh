#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the actual frontier reader without booting a node or opening a
# datadir. Optional --bench times 300 reads; optional PATH selects a baseline.
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script="${1:-$SCRIPT_DIR/step1_refold_rate_proof.sh}"
[ "$#" -le 1 ] || { echo 'usage: step1_refold_parser_selftest.sh [--bench] [PATH]' >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zcl-refold-parser.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

# Only load these two functions. Never source the harness's live entry point.
sed -n '/^_hstar_from() {/,/^}/p; /^read_hstar() {/,/^}/p' "$script" > "$tmp/readers.sh"
. "$tmp/readers.sh"
declare -F _hstar_from read_hstar >/dev/null
checks=0
check() {
    local got
    got="$(_hstar_from "$2")"
    [ "$got" = "$3" ] || {
        printf 'refold-parser: FAIL %s: got <%s>, expected <%s>\n' "$1" "$got" "$3" >&2
        exit 1
    }
    checks=$((checks + 1))
}
check authoritative '{"hstar":42,"cached_provable_tip":99}' 42
check zero '{"hstar":0,"cached_provable_tip":99}' 0
check unknown '{"hstar":-1,"cached_provable_tip":99}' 99
check absent '{"cached_provable_tip":99}' 99
check empty '{}' ''
check busy '{"snapshot_status":"progress_store_busy","retryable":true}' ''
check negative '{"hstar":-2,"cached_provable_tip":99}' -2
check no-cache '{"hstar":-1}' ''
check unknown-cache '{"hstar":-1,"cached_provable_tip":-1}' -1
check exact-key '{"hstar_next_height":7,"hstar":42}' 42
check duplicate '{"hstar":42,"hstar":99}' 42
check duplicate-unknown '{"hstar":-1,"hstar":42,"cached_provable_tip":99}' 99
check first-integer '{"hstar":null,"hstar":"7","hstar":42}' 42
check wide '{"hstar":18446744073709551615}' 18446744073709551615
check leading-zeros '{"hstar":00042}' 00042
check integer-prefix '{"hstar":42.5}' 42
check multiline $'{\n"hstar" \t: 42,\n"hstar":99}' 42
check split-field $'{"hstar"\n:42}' ''
check whitespace $'{"hstar"\r\v\f:\t42}' 42
check cache-duplicate '{"cached_provable_tip":42,"cached_provable_tip":99}' 42

# Preserve the two CLI forms: retry only when the first read has no height.
rpc() {
    printf '%s\n' "$*" >> "$tmp/rpc.calls"
    if [ "$2" = reducer_frontier ]; then printf '%s' "$first";
    else printf '%s' '{"hstar":73}'; fi
}
first='{"hstar":42}'
[ "$(read_hstar)" = 42 ]
[ "$(wc -l < "$tmp/rpc.calls")" -eq 1 ]
: > "$tmp/rpc.calls"
first='{}'
[ "$(read_hstar)" = 73 ]
printf 'dumpstate reducer_frontier\ndumpstate "reducer_frontier"\n' > "$tmp/expected.calls"
cmp "$tmp/rpc.calls" "$tmp/expected.calls"
checks=$((checks + 2))
printf 'refold-parser: PASS (%s field/fallback checks)\n' "$checks"

if [ "$bench" -eq 1 ]; then
    TIMEFORMAT='refold-parser: 300 reads wall=%3R user=%3U sys=%3S'
    time for ((i=0; i<100; i++)); do
        _hstar_from '{"hstar":42,"cached_provable_tip":99}' >/dev/null || exit 1
        _hstar_from '{"hstar":-1,"cached_provable_tip":99}' >/dev/null || exit 1
        _hstar_from '{"retryable":true}' >/dev/null || exit 1
    done
fi

# Deterministic observer-cost gate; count each old parser subprocess even
# when it runs inside a command substitution. Timing is informational only.
grep() { printf 'grep\n' >> "$tmp/parsers"; command grep "$@"; }
head() { printf 'head\n' >> "$tmp/parsers"; command head "$@"; }
: > "$tmp/parsers"
_hstar_from '{"hstar":42}' >/dev/null || exit 1
_hstar_from '{"hstar":-1,"cached_provable_tip":99}' >/dev/null || exit 1
_hstar_from '{}' >/dev/null || exit 1
count="$(wc -l < "$tmp/parsers")"
printf 'refold-parser: external parser processes for three reads=%s (required 0)\n' "$count"
[ "$count" -eq 0 ]
