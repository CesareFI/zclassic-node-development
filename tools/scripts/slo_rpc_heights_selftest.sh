#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic RPC height observer regression; no node, network or datadir.
# Usage: bash tools/scripts/slo_rpc_heights_selftest.sh [--bench] [probe-script]
set -euo pipefail
export LC_ALL=C
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir="$(cd "$(dirname "$0")" && pwd)"
probe="${1:-$script_dir/node_slo_probe.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-slo-rpc-heights.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Load only the production observer functions, without collector dispatch or
# host discovery. Also accepts the old probe to reproduce the process budget.
sed -n '/^rpc_heights() {/,/^}/p; /^rpc_probe() {/,/^}/p' "$probe" > "$fixture/functions"
# shellcheck source=/dev/null
. "$fixture/functions"
declare -F rpc_probe > /dev/null
unset SLO_TEST_OVERRIDE
response=''
command_status=0
# Fixed command output and clock isolate parsing from RPC/clock process cost.
bash() { printf '%s' "$response"; return "$command_status"; }
date() { printf '1700000000000000000\n'; }
failures=0
cases=0

check() {
    local label="$1" expected actual served header tail=''
    response="$2"
    # Reference the exact previous per-field semantics, not a JSON decoder.
    served="$(printf '%s' "$response" | sed -n 's/.*"blocks":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
    header="$(printf '%s' "$response" | sed -n 's/.*"headers":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
    if [ -z "$served" ]; then
        tail="$(printf '%s' "$response" | tr '\n' ' ' | cut -c1-200)"
        [ -n "$tail" ] || tail=empty_response
    fi
    printf -v expected '%s\x1f%s\x1f0\x1f%s' "$served" "$header" "$tail"
    actual="$(rpc_probe ignored SLO_TEST_OVERRIDE)"
    cases=$((cases + 1))
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected=%q\nactual=%q\n' "$label" "$expected" "$actual" >&2
        failures=$((failures + 1))
    fi
}

check empty ''
check compact '{"result":{"blocks":3200000,"headers":3200001}}'
check reversed '{"headers":20,"blocks":10}'
check zero '{"blocks":0,"headers":0}'
check missing-blocks '{"headers":900}'
check missing-headers '{"blocks":800}'
check neither '{"error":"unavailable"}'
check pretty $'{\n "blocks": 12,\n "headers":\t13\n}'
check whitespace $'{"blocks":\r\t\v\f 0012,"headers": 0013}'
check duplicates '{"blocks":1,"blocks":2,"headers":3,"headers":4}'
check multiple-lines $'{"blocks":1}\n{"headers":2}\n{"blocks":3,"headers":4}'
check wide '{"blocks":18446744073709551615,"headers":9007199254740993}'
check key-boundaries '{"numblocks":42,"headers_extra":43}'
check negative '{"blocks":-1,"headers":-2}'
check split-value $'{"blocks":\n9,"headers":\n10}'
check space-before-colon '{"blocks" :9,"headers" :10}'
check numeric-prefix '{"blocks":12.5,"headers":13e2}'
check trailing-no-newline $'diagnostic\n{"blocks":12,"headers":13}'
command_status=7
check command-failure 'RPC unavailable'
check failed-prefix '{"blocks":12,"headers":13}'
command_status=0
printf -v long '%8192s' ''
check long-response "${long}{\"blocks\":12,\"headers\":13}${long}"
printf 'height observer: %s byte comparisons, %s failures\n' "$cases" "$failures"

: > "$fixture/tools"
response='{"result":{"blocks":3200000,"headers":3200001}}'
(
    sed() { echo sed >> "$fixture/tools"; command sed "$@"; }
    head() { echo head >> "$fixture/tools"; command head "$@"; }
    awk() { echo awk >> "$fixture/tools"; command awk "$@"; }
    rpc_probe ignored SLO_TEST_OVERRIDE > /dev/null
)
count="$(wc -l < "$fixture/tools")"
printf 'height parsing processes per healthy observation: %s (baseline: 4)\n' "$count"
if [ "$count" -gt 1 ]; then
    echo 'FAIL: height parsing exceeded one external process' >&2
    failures=$((failures + 1))
fi
if [ "$bench" = 1 ]; then
    echo 'benchmark: 500 healthy observations; fixed RPC/clock, warm host caches'
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time (
        for ((i=0; i<500; i++)); do
            actual="$(rpc_probe ignored SLO_TEST_OVERRIDE)"
            [ "$actual" = $'3200000\x1f3200001\x1f0\x1f' ] || exit 1
        done
    )
fi
[ "$failures" -eq 0 ] || exit 1
echo 'selftest: PASS RPC height observer'
