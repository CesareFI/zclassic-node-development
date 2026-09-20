#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Recovery observer regression/benchmark. No node, datadir or network needed.
# Usage: bash tools/scripts/netdisrupt_tip_readability_selftest.sh [--bench] [harness]
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
harness=${1:-$script_dir/network_disruption_recovery_stopwatch.sh}
fixture=$(mktemp -d /tmp/zcl-tip-readable.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n '/^network_tip_readable()/,/^}/p' "$harness" > "$fixture/helper.sh"
. "$fixture/helper.sh"
# Exercise the real preflight expression, including its command substitution
# on the baseline. Both call sites must use the same expression.
observation=$(sed -n '/^pre_nt_ok=/p' "$harness")
poll=$(sed -n '/^    nt_ok=/s/^    //p' "$harness")
[[ -n $observation && ${observation//pre_/} == "$poll" ]] || {
    echo 'FAIL: missing or divergent preflight/poll observers' >&2; exit 1;
}
observe() {
    local pre_fj=$1 pre_nt_ok=''
    eval "$observation" || : # grep returns 1 for an absent true field.
    [[ -n $pre_nt_ok ]]
}
check() {
    local expected=$1 document=$2 actual=1
    if observe "$document"; then actual=0; fi
    [[ $actual == "$expected" ]] || {
        printf 'FAIL: expected status %s, got %s: %q\n' "$expected" "$actual" "$document" >&2
        exit 1
    }
}
check 0 '{"network_tip_read_ok":true}'
check 1 '{"network_tip_read_ok":false}'
check 1 '{"network_tip_read_ok":"true"}'
check 1 '{"network_tip_read_ok":null}'
check 1 ''
check 1 '{"not_network_tip_read_ok":true,"network_tip_read_ok_extra":true}'
check 0 $'{"network_tip_read_ok"\t\r\v\f : \t\r\v\ftrue}'
check 0 $'{\n"network_tip_read_ok":true\n}'
check 1 $'{"network_tip_read_ok"\n:true}'
check 1 $'{"network_tip_read_ok":\ntrue}'
# Preserve the existing presence/prefix policy, including duplicate keys.
check 0 '{"network_tip_read_ok":false,"network_tip_read_ok":true}'
check 0 '{"network_tip_read_ok":true,"network_tip_read_ok":false}'
check 0 '{"network_tip_read_ok":true_suffix}'
printf -v padding '%131072s' ''
check 0 "${padding}{\"network_tip_read_ok\":true}"
check 1 "${padding}{\"network_tip_read_ok\":false}"
echo 'PASS: 15 readability cases, including line boundaries and large input'

doc='{"hstar":3107000,"network_tip":3190019,"network_tip_read_ok":true}'
if (( bench )); then
    TIMEFORMAT='1000 readability observations: wall=%3R user=%3U sys=%3S seconds'
    for ((run=0; run<3; run++)); do
        time for ((i=0; i<1000; i++)); do observe "$doc"; done
    done
fi
: > "$fixture/calls"
grep() { printf 'grep\n' >> "$fixture/calls"; command grep "$@"; }
for ((i=0; i<100; i++)); do observe "$doc"; done
calls=$(wc -l < "$fixture/calls")
unset -f grep
printf '100 readability observations: external grep calls=%s\n' "$calls"
[[ $calls == 0 ]] || { echo 'FAIL: polling still starts grep' >&2; exit 1; }
(
    PATH=/nonexistent
    check 0 "$doc"
    check 1 '{"network_tip_read_ok":false}'
)
echo 'PASS: no external tools in readability observation'
