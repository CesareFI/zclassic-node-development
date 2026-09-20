#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the actual C3 polling decisions without launching a node or RPC.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_file="${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}"
fixture="$(mktemp -d /tmp/z23-tip-heights.XXXXXX)"
trap 'rm -rf "$fixture"' EXIT

# Only the parser and polling decision are loaded, never the live harness.
awk '/^parse_tip_heights\(\)/ {copy=1} copy {print} copy && /^}/ {exit}' \
    "$source_file" > "$fixture/parser.sh"
awk '/    # getblockchaininfo is param-free/ {copy=1; next}
     copy && /    sleep 5|    # Observation work consumes/ {exit} copy {print}' \
    "$source_file" > "$fixture/poll.sh"
[[ -s "$fixture/poll.sh" ]] || { echo 'FAIL: polling body absent' >&2; exit 1; }
. "$fixture/parser.sh"
note_seed_ready() { :; }
read_tip_sample() { :; }
fixture_rpc() { printf '%s\n' "$bci"; }
mark_seeded() { seeded=1; }
sed() { printf 'sed\n' >> "$fixture/processes"; command sed "$@"; }
grep() { printf 'grep\n' >> "$fixture/processes"; command grep "$@"; }

sample() {
    bci="$1" PEER_TIP=3200000 elapsed=10 reached=0 seeded=0 last_h=-1 last_hdr=-1
    RPC_BIN=fixture_rpc DATADIR="$fixture" RPC=39071
    h=stale hdr=stale
    for once in 1; do
        . "$fixture/poll.sh"
    done
}

if [[ "${2:-}" == --bench ]]; then
    : > "$fixture/processes"
    TIMEFORMAT='poll_parse_seconds=%3R'
    time for ((i=0; i<200; i++)); do
        sample '{"blocks":3200000,"headers":3200000}' > /dev/null
    done
    printf 'samples=200 external_text_tools=%s\n' "$(wc -l < "$fixture/processes")"
    exit 0
fi

failures=0
check() {
    local name="$1" reply="$2" want_reached="$3" want_h="$4"
    : > "$fixture/processes"
    sample "$reply" > "$fixture/output"
    if [[ "$reached" != "$want_reached" || "$last_h" != "$want_h" ]]; then
        printf 'FAIL: %s reached=%s height=%s (want %s/%s)\n' \
            "$name" "$reached" "$last_h" "$want_reached" "$want_h" >&2
        failures=$((failures + 1))
    fi
    if [[ -s "$fixture/processes" ]]; then
        printf 'FAIL: %s launches external text tools\n' "$name" >&2
        failures=$((failures + 1))
    fi
}
check compact '{"blocks":3200000,"headers":3200000}' 1 3200000
check pretty $'{\n "headers" : 3200000,\n "blocks" : 3200000\n}' 1 3200000
check below-tip '{"blocks":3199999,"headers":3200000}' 0 3199999
check unequal '{"blocks":3200000,"headers":3200001}' 0 3200000
check above-tip '{"blocks":3200001,"headers":3200001}' 1 3200001
check genesis '{"blocks":0,"headers":0}' 0 0
check negative '{"blocks":-1,"headers":3200000}' 0 -1
check absent '{}' 0 -1
check missing-headers '{"blocks":3200000}' 0 3200000
check null '{"blocks":null,"headers":3200000}' 0 -1
check quoted '{"blocks":"3200000","headers":3200000}' 0 -1
check decimal '{"blocks":3200000.5,"headers":3200000}' 0 -1
check exponent '{"blocks":3200000e1,"headers":3200000}' 0 -1
check suffix '{"blocks":3200000oops,"headers":3200000}' 0 -1
check key-prefix '{"blocks_extra":3200000,"headers":3200000}' 0 -1
[[ "$failures" == 0 ]] || exit 1
echo 'cold-start tip heights: PASS (15 isolated polling cases, no text-tool processes)'
