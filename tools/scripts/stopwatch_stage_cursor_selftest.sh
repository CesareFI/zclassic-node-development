#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Isolated frontier observer regression and optional benchmark; no node/RPC.
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
fixture=$(mktemp -d /tmp/z23-stage-cursor.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
sed -n '/^frontier_stage_cursor() {/,/^}/p' "$subject" > "$fixture/reader.sh"
. "$fixture/reader.sh"
declare -F frontier_stage_cursor >/dev/null || { echo 'missing cursor reader' >&2; exit 1; }
check() {
    local actual
    actual=$(frontier_stage_cursor "$2" "${3:-header_admit}")
    [[ $actual == "$1" ]] || {
        printf 'FAIL cursor: expected <%s>, got <%s>\n' "$1" "$actual" >&2
        exit 1
    }
}
doc='{"hstar":100,"stage_cursors":[{"stage":"header_admit","cursor":4211},{"stage":"body_persist","cursor":77}]}'
check 4211 "$doc"
check 77 "$doc" body_persist
check -1 "$doc" validate_headers
check -1 ''
check -1 '{}'
check 0 '{"stage":"header_admit","cursor":0}'
check -12 '{"cursor": -12,"stage":"header_admit"}'
check 7 '{"stage":"header_admit","cursor":0007}'
check -1 '{"stage":"header_admit_extra","cursor":9}'
check -1 '{"stage":"header_admit","cursor_extra":9}'
check -1 '{"stage":"header_admit","cursor":null},{"stage":"body_persist","cursor":9}'
check -1 '{"stage":"header_admit","cursor":"9"}'
# Retain the compact native dump reader policy, including line boundaries.
check -1 '{"stage": "header_admit","cursor":9}'
check -1 $'{"stage":"header_admit",\n"cursor":9}'
check 8 $'{"stage":"body_persist","cursor":9},\n{"stage":"header_admit","cursor":8}'
check 2 '{"stage":"header_admit","cursor":1},{"stage":"header_admit","cursor":2}'
check 1 '{"stage":"header_admit","cursor":1,"cursor":2}'
check 1 '{"stage":"header_admit","cursor":1},{"stage":"header_admit","cursor":null}'
# Input bigger than a pipe buffer; an early match must not cause SIGPIPE.
printf -v padding '%131072s' ''
check 4211 "${doc%\}} ,\"padding\":\"$padding\"}"
check 4211 "{\"padding\":\"$padding\",${doc#\{}"
printf 'stage cursor values: PASS\n'

observe_tool() {
    local tool=$1
    shift
    printf '%s\n' "$tool" >> "$fixture/calls"
    command "$tool" "$@"
}
awk() { observe_tool awk "$@"; }
tr() { observe_tool tr "$@"; }
: > "$fixture/calls"
check 4211 "$doc"
check 77 "$doc" body_persist
calls=$(wc -l < "$fixture/calls")
printf 'two stage cursor reads: external_tools=%s\n' "$calls"
unset -f awk tr
if (( bench )); then
    TIMEFORMAT='500 poll pairs: %3R s wall, %3U s user, %3S s system'
    time for ((i=0;i<500;i++)); do
        frontier_stage_cursor "$doc" header_admit > /dev/null
        frontier_stage_cursor "$doc" body_persist > /dev/null
    done
fi
[[ $calls == 2 ]] || { echo 'FAIL: expected one external tool per cursor read' >&2; exit 1; }
printf 'stage cursor process budget: PASS\n'
