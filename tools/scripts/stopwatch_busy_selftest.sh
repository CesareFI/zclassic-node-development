#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Local polling regression; no node, RPC, datadir, or network access.
# Usage: bash tools/scripts/stopwatch_busy_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
if (( $# > 1 )); then
    printf 'usage: %s [--bench] [library]\n' "$0" >&2
    exit 2
fi
. "${1:-$(dirname "${BASH_SOURCE[0]}")/stopwatch_json_lib.sh}"

check_busy() {
    local label=$1 expected=$2 document=$3 rc=0
    is_busy_response "$document" || rc=$?
    if [[ $rc != "$expected" ]]; then
        printf 'FAIL %s: expected status %s, got %s\n' "$label" "$expected" "$rc" >&2
        exit 1
    fi
}

check_busy busy 0 '{"snapshot_status":"progress_store_busy","retryable":true}'
check_busy frontier 1 '{"hstar":3107923,"network_tip":3190019}'
check_busy false 1 '{"retryable":false}'
check_busy quoted 1 '{"retryable":"true"}'
check_busy null 1 '{"retryable":null}'
check_busy empty 1 ''
check_busy similar-key 1 '{"not_retryable":true,"retryable_extra":true}'
check_busy spaces 0 $'{"retryable" \t\r\v\f: \t\r\v\ftrue}'
check_busy multiline 0 $'{\n"hstar":-1,\n"retryable":true\n}'
# Preserve grep's line-local matching and existing prefix/duplicate behavior.
# This helper classifies the existing telemetry shape, not arbitrary JSON.
check_busy split-colon 1 $'{"retryable"\n:true}'
check_busy split-value 1 $'{"retryable":\ntrue}'
check_busy duplicate 0 '{"retryable":false,"retryable":true}'
check_busy prefix 0 '{"retryable":true_suffix}'
printf 'stopwatch-busy: classification PASS (13 cases)\n'

if (( bench )); then
    fixture='{"cached_provable_tip":3107000,"snapshot_status":"progress_store_busy","retryable":true}'
    TIMEFORMAT='stopwatch-busy: 1000 reads: wall=%3R user=%3U sys=%3S seconds'
    time for ((i=0; i<1000; i++)); do is_busy_response "$fixture"; done
fi

# Enforce the observer-cost contract independently of noisy wall-clock timing.
(
    PATH=/nonexistent
    check_busy no-external-tools 0 '{"retryable":true}'
    check_busy no-external-tools-false 1 '{"retryable":false}'
)
printf 'stopwatch-busy: no external tools PASS\n'
