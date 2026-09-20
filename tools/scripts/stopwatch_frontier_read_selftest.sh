#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise actual stopwatch RPC readers with local fixtures; no node or sleep.
# Usage: bash tools/scripts/stopwatch_frontier_read_selftest.sh [--bench] [script-dir]
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts}
fixture=$(mktemp -d /tmp/z23-frontier-read.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
. "$root/tools/scripts/stopwatch_json_lib.sh"
failed=0

# RPC runs in command substitution, so retain its call counter in the fixture.
rpc() {
    local count
    read -r count < "$fixture/count"
    printf '%s\n' "$((count + 1))" > "$fixture/count"
    if [[ $mode == repeat || $count == 0 ]]; then printf '%s' "$response"; fi
}
sleep() { delay=$((delay + $1)); }
run_case() {
    local label=$1 expected_calls=$2 expected_delay=$3 expected_busy=$4 expected=$5
    local delay=0 count
    printf '0\n' > "$fixture/count"
    FRONTIER_LAST_BUSY=0
    rpc_frontier > "$fixture/result"
    read -r count < "$fixture/count"
    printf '%s' "$expected" > "$fixture/expected"
    if [[ $count != "$expected_calls" || $delay != "$expected_delay" ||
          $FRONTIER_LAST_BUSY != "$expected_busy" ]] ||
       ! cmp -s "$fixture/result" "$fixture/expected"; then
        printf 'FAIL %s: RPCs=%s backoff=%ss busy=%s (expected %s/%ss/%s); response equality checked\n' \
            "$label" "$count" "$delay" "$FRONTIER_LAST_BUSY" \
            "$expected_calls" "$expected_delay" "$expected_busy" >&2
        failed=1
    else
        printf 'PASS %s: RPCs=%s backoff=%ss busy=%s\n' \
            "$label" "$count" "$delay" "$FRONTIER_LAST_BUSY"
    fi
}

# A large valid JSON document, with the match before enough text to overflow
# the pipe buffer. It also covers a pretty-printed multiline response.
printf -v padding '%1048576s' ''
for script in cold_start_to_tip_stopwatch.sh network_disruption_recovery_stopwatch.sh; do
    sed -n '/^rpc_frontier() {/,/^}/p' "$subject/$script" > "$fixture/reader.sh"
    unset -f rpc_frontier 2>/dev/null || true
    . "$fixture/reader.sh"
    declare -F rpc_frontier >/dev/null || { echo "missing reader: $script" >&2; exit 1; }
    mode=repeat
    response='{"hstar":123,"network_tip":456}'
    run_case "$script small frontier" 1 0 0 "$response"
    for mode in repeat once; do
        response=$'{"hstar":123,\n"padding":"'"$padding"'"}'
        run_case "$script large early match ($mode)" 1 0 0 "$response"
    done
    mode=repeat
    response='{"padding":"'"$padding"'","hstar":123}'
    run_case "$script large late match" 1 0 0 "$response"
    response='{"snapshot_status":"progress_store_busy","retryable":true}'
    run_case "$script busy" 6 12 1 "$response"
    mode=once
    if [[ $script == cold_start_to_tip_stopwatch.sh ]]; then
        run_case "$script retains busy partial" 6 12 1 "$response"
    else
        run_case "$script retains last response policy" 6 12 0 ''
    fi
    mode=repeat
    response='{"cached_hstar":123}'
    run_case "$script similar key" 6 12 0 "$response"
    response=''
    run_case "$script empty" 6 12 0 ''
    if (( bench )); then
        response='{"hstar":123,"network_tip":456}'
        printf '0\n' > "$fixture/count"
        delay=0
        TIMEFORMAT='100 frontier reads: %3R s wall, %3U s user, %3S s system'
        time for ((i=0;i<100;i++)); do rpc_frontier > /dev/null; done
    fi
done
exit "$failed"
