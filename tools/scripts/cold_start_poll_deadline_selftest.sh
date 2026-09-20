#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise the real time-to-tip poll loop with an in-process clock and RPC
# doubles. No node, network, datadir, or real sleeps are involved.
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}
fixture=$(mktemp -d /tmp/z23-c3-poll-deadline.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
sed -n '/^reached=0$/,/^done$/p' "$subject" > "$fixture/loop.sh"
[[ -s $fixture/loop.sh ]] || { echo 'FAIL: poll loop absent' >&2; exit 1; }
date() { printf '%s\n' "$clock"; }
kill() { return 0; }
note_seed_ready() { :; }
parse_tip_heights() { h=$sample_height hdr=$sample_height; }
mark_seeded() { clock=$((clock + seed_cost)); }
read_tip_sample() {
    polls=$((polls + 1))
    clock=$((clock + rpc_cost))
    elapsed=$((clock - start))
    [[ $elapsed -lt $BUDGET ]]
}
sleep() {
    [[ $1 -gt 0 && $1 -le 5 ]] || { echo 'FAIL: invalid pause' >&2; exit 1; }
    pauses+=("$1")
    clock=$((clock + $1))
}
run_case() {
    local name=$1 BUDGET=$2 rpc_cost=$3 expected_pauses=$4 expected_polls=$5
    local start=100 clock=100 polls=0 elapsed=0 now=100 PID=1 reached=0 h='' hdr=''
    local remaining=0
    local sample_height=${6:-} seed_cost=${7:-0} PEER_TIP=2000000 last_h=-1 last_hdr=-1
    local -a pauses=()
    . "$fixture/loop.sh"
    printf '%s: budget=%s elapsed=%s pauses=[%s] polls=%s\n' \
        "$name" "$BUDGET" "$((clock - start))" "${pauses[*]}" "$polls"
    if (( ! baseline )); then
        [[ $((clock - start)) == "$BUDGET" && ${pauses[*]} == "$expected_pauses" &&
           $polls == "$expected_polls" && $reached == 0 ]] || {
            echo "FAIL: $name exceeded budget or changed polling cadence" >&2
            exit 1
        }
    fi
}
run_case 'one-second budget' 1 0 '1' 1
run_case 'partial final interval' 6 0 '5 1' 2
run_case 'ordinary cadence' 10 0 '5 5' 2
run_case 'RPC consumes final interval' 10 2 '5 1' 2
run_case 'RPC exhausts budget' 2 2 '' 1
run_case 'seed observation exhausts budget' 4 2 '' 1 1000000 2
if (( ! baseline )); then echo 'PASS: time-to-tip poll deadline and cadence'; fi
