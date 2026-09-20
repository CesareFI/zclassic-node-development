#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic peer-handshake observer regression and optional cost benchmark.
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
fixture=$(mktemp -d /tmp/z23-handshake-observer.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
# Load just the production reader; never run harness setup or start a node.
sed -n '/^pl_handshake_unix() {/,/^}/p' "$subject" > "$fixture/reader.sh"
. "$fixture/reader.sh"
declare -F pl_handshake_unix >/dev/null || { echo 'missing handshake reader' >&2; exit 1; }
check() {
    local actual
    actual=$(pl_handshake_unix "$2" "${3:-1}")
    [[ $actual == "$1" ]] || {
        printf 'FAIL handshake: expected <%s>, got <%s>\n' "$1" "$actual" >&2
        exit 1
    }
}
doc='{"peers":[{"peer_id":1,"handshake_complete_at":1700000040,"advertised_height":100},{"peer_id":2,"handshake_complete_at":1700000020,"advertised_height":200},{"peer_id":3,"handshake_complete_at":1700000010,"advertised_height":0}]}'
check 1700000020 "$doc"
check 1700000010 "$doc" 0
check -1 ''
check -1 '{}'
check -1 '{"peer_id":1,"handshake_complete_at":0,"advertised_height":10}'
check -1 '{"peer_id":1,"handshake_complete_at":-1,"advertised_height":10}'
check -1 '{"handshake_complete_at":4,"advertised_height":10}'
check -1 '{"peer_id":1,"handshake_complete_at":4,"advertised_height_trusted":10}'
check -1 '{"peer_id":1,"handshake_complete_at":4,"advertised_height":null}'
check -1 '{"peer_id":1,"handshake_complete_at":4,"advertised_height":-1}'
check 4 '{"peer_id":1,"handshake_complete_at":4}' 0
check -1 '{"peer_id":1,"handshake_complete_at":"4","advertised_height":10}'
check 4 $'{"peer_id":1,"handshake_complete_at" \t: \t4,"advertised_height":10}'
# A timestamp and height must belong to the same compact peer record.
check -1 '{"peer_id":1,"handshake_complete_at":4},{"peer_id":2,"advertised_height":10}'
check -1 '{"peer_id":1,"handshake_complete_at":4,"nested":{"advertised_height":10}}'
check -1 $'{"peer_id":1,"handshake_complete_at":4,\n"advertised_height":10}'
check 3 $'{"peer_id":1,"handshake_complete_at":4,"advertised_height":10},\n{"peer_id":2,"handshake_complete_at":3,"advertised_height":20}'
# Preserve first field match, earliest peer selection and numeric conversion.
check 4 '{"peer_id":1,"handshake_complete_at":4,"handshake_complete_at":2,"advertised_height":10}'
check 4 '{"peer_id":1,"handshake_complete_at":0004,"advertised_height":10}'
check 4 '{"peer_id":1,"handshake_complete_at":4,"advertised_height":10},{"peer_id":2,"handshake_complete_at":5,"advertised_height":20}'
printf -v padding '%131072s' ''
check 1700000020 "$padding$doc"
check 1700000020 "$doc$padding"
printf 'handshake observer values: PASS\n'

observe_tool() {
    local tool=$1
    shift
    printf '%s\n' "$tool" >> "$fixture/calls"
    command "$tool" "$@"
}
awk() { observe_tool awk "$@"; }
tr() { observe_tool tr "$@"; }
: > "$fixture/calls"
check 1700000020 "$doc"
calls=$(wc -l < "$fixture/calls")
printf 'handshake observer per poll: external_tools=%s\n' "$calls"
unset -f awk tr
if (( bench )); then
    TIMEFORMAT='500 observations: %3R s wall, %3U s user, %3S s system'
    time for ((i=0;i<500;i++)); do
        pl_handshake_unix "$doc" > /dev/null
    done
fi
[[ $calls == 1 ]] || { echo 'FAIL: expected one external tool per handshake read' >&2; exit 1; }
printf 'handshake observer process budget: PASS\n'
