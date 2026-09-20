#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Run the shipped time-to-tip loop with failed/successful RPC observations.
# Usage: bash tools/scripts/cold_start_rpc_status_selftest.sh [--baseline] [probe.sh]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$ROOT/tools/scripts/cold_start_to_tip_probe.sh}
fixture=$(mktemp -d /tmp/zcl-c3-rpc-status.XXXXXX)
trap 'rm -rf "$fixture"' EXIT

# Extract production functions and the whole acceptance loop, not a model of
# its height predicate. Missing delimiters fail instead of silently passing.
sed -n '/^parse_tip_heights() {/,/^}/p; /^read_tip_sample() {/,/^}/p' \
    "$subject" > "$fixture/functions.sh"
awk '/^reached=0$/ { copy=1 } copy { print } copy && /^done$/ { exit }' \
    "$subject" > "$fixture/loop.sh"
grep -q '^read_tip_sample() {' "$fixture/functions.sh"
grep -q '^parse_tip_heights() {' "$fixture/functions.sh"
grep -q '^done$' "$fixture/loop.sh"
. "$fixture/functions.sh"

check() {
    if [[ $1 != "$2" ]]; then
        printf 'FAIL: %s expected=%s actual=%s\n' "$3" "$2" "$1" >&2
        exit 1
    fi
}

# Overrides are confined to this fixture process; there is no child node,
# socket, datadir, or real sleep. The clock file crosses RPC command substitution.
date() { read -r clock < "$fixture/clock"; printf '%s\n' "$clock"; }
# Keep the virtual-clock function RPC local. Real timeout/process behavior is
# exercised separately by cold_start_rpc_budget_selftest.sh.
timeout() {
    [[ $1 == --kill-after=1 && $2 -gt 0 ]] || exit 1
    shift 2
    "$@"
}
kill() { return 0; }
sleep() {
    read -r clock < "$fixture/clock"
    printf '%s\n' "$((clock + $1))" > "$fixture/clock"
}
note_seed_ready() { :; }
mark_seeded() { seeded=1; }
fixture_rpc() {
    check "$*" getblockchaininfo 'RPC method'
    local calls clock
    read -r calls < "$fixture/calls"
    read -r clock < "$fixture/clock"
    calls=$((calls + 1))
    printf '%s\n' "$calls" > "$fixture/calls"
    printf '%s\n' "$((clock + rpc_delay))" > "$fixture/clock"
    printf '%s\n' "$reply"
    if [[ $recover == 1 && $calls -gt 1 ]]; then return 0; fi
    return "$rpc_status"
}

run_case() {
    local label=$1 expected=$2 expected_elapsed=$3
    local start=100 BUDGET=10 DATADIR=$fixture RPC=39071 RPC_BIN=fixture_rpc
    local PID=42 PEER_TIP=3200000 seeded=0 last_h=-1 last_hdr=-1
    local now elapsed bci h hdr reached
    printf '100\n' > "$fixture/clock"
    printf '0\n' > "$fixture/calls"
    . "$fixture/loop.sh" > "$fixture/output"
    printf 'case=%s reached=%s elapsed=%s last_height=%s\n' \
        "$label" "$reached" "$elapsed" "$last_h"
    if [[ $baseline == 0 ]]; then
        check "$reached" "$expected" "$label verdict"
        check "$elapsed" "$expected_elapsed" "$label elapsed"
        if [[ $expected == 0 ]]; then
            check "$seeded" 0 "$label must not establish seeded authority"
            check "$last_h" -1 "$label must not record failed heights"
        fi
    fi
}

reply='{"blocks":3200000,"headers":3200000}'
rpc_delay=1 recover=0 rpc_status=0
run_case success 1 1
for rpc_status in 1 7 124; do
    run_case "failed-$rpc_status" 0 10
done
reply='{"blocks":3200000,"headers":3200000,"unfinished":'
run_case failed-partial 0 10
reply='{"blocks":3200000,"headers":3200000}'
rpc_status=7 recover=1
run_case recovery 1 7
recover=0 rpc_status=0 rpc_delay=10
run_case deadline 0 10
rpc_status=124
run_case failed-at-deadline 0 10
rpc_status=0 rpc_delay=1 reply=''
run_case empty 0 10
reply='{"blocks":3200000.5,"headers":3200000}'
run_case malformed 0 10
if [[ $baseline == 0 ]]; then
    echo 'PASS: successful, failed, recovered, late and missing time-to-tip observations'
fi
