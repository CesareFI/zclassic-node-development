#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic block-height polling regression; no nodes or network are used.
# Usage: bash tools/scripts/netdisrupt_height_selftest.sh [--bench] [drill]
set -euo pipefail
export LC_ALL=C
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir="$(cd "$(dirname "$0")" && pwd)"
drill="${1:-$script_dir/netdisrupt_two_node_drill.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-nd2-height.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Load only the real polling function, never the drill's operational entry.
definition="$(awk '/^nd2_blockcount\(\) \{/{copy=1} copy{print} copy && /^}/{exit}' "$drill")"
test -n "$definition"
eval "$definition"
nd2_rpc() {
    [ "$#" = 3 ] && [ "$1" = fixture-datadir ] &&
        [ "$2" = 39051 ] && [ "$3" = getblockcount ] || return 1
    printf '%s' "$response"
}
check() {
    local label="$1" expected="$3" actual
    response="$2"
    actual="$(nd2_blockcount fixture-datadir 39051)"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL %s: expected <%s>, got <%s>\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
    printf '  ok: %s\n' "$label"
}
check genesis '{"result":0,"error":null}' 0
check height '{"result":3224110,"error":null,"id":1}' 3224110
check negative '{"result":-1}' -1
check wide '{"result":9223372036854775807}' 9223372036854775807
check empty '' ''
check missing '{"error":"unreachable"}' ''
check null '{"result":null}' ''
check quoted '{"result":"42"}' ''
check whitespace '{"result" : 42}' 42
check exact-key '{"result_extra":9,"result":42}' 42
check last-match '{"result":3,"result":42}' 42
check last-null '{"result":3,"result":null}' ''
check multiline $'{\n  "result":42,\n  "error":null\n}' 42
check multiple-lines $'{"result":3}\n{"result":42}' $'3\n42'
# Preserve the existing narrow reader's treatment of noncanonical input.
check tab '{"result":	42}' ''
check numeric-prefix '{"result":42.5}' 42
check dash-text '{"result":--1}' --1

# Differential fixtures retain the old sed semantics as the oracle. Polling
# callers use command substitution, so trailing newlines are not observable.
for response in $'noise\n{"result":0}\n' $'{"result":4}\n{"result":null}' \
    '{"result":: 003}' $'{"result":4}\r\n{"result":5}' \
    '{"result": 3, "nested":{"result":7}}'; do
    expected="$(printf '%s' "$response" | sed -n 's/.*"result"[: ]*\([0-9-]*\).*/\1/p')"
    actual="$(nd2_blockcount fixture-datadir 39051)"
    test "$actual" = "$expected"
done

# Count text-tool invocations independently of host load and elapsed time.
: > "$fixture/tools"
response='{"result":3224110,"error":null,"id":1}'
(
    sed() { echo sed >> "$fixture/tools"; command sed "$@"; }
    nd2_blockcount fixture-datadir 39051 > /dev/null
)
tool_count="$(wc -l < "$fixture/tools")"
printf 'sed processes per height poll: %s (baseline: 1)\n' "$tool_count"
if [ "$bench" = 1 ]; then
    echo 'benchmark: 1000 mock-RPC height polls, warm host caches'
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time (
        for ((i=0; i<1000; i++)); do
            actual="$(nd2_blockcount fixture-datadir 39051)"
            test "$actual" = 3224110
        done
    )
fi
if [ "$tool_count" -ne 0 ]; then
    echo 'selftest: FAIL height polling still launches sed' >&2
    exit 1
fi
echo 'selftest: PASS netdisrupt height polling'
