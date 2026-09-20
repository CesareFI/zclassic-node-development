#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Run the real phase observer with fixture responses; never start a node.
# Usage: bash tools/scripts/stopwatch_stage_pair_selftest.sh [--bench] [subject]
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
fixture=$(mktemp -d /tmp/z23-stage-pair.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
sed -n '/^frontier_stage_cursor() {/,/^}/p; /^phase_observe() {/,/^}/p' \
    "$subject" > "$fixture/observer.sh"
. "$fixture/observer.sh"
declare -F frontier_stage_cursor >/dev/null
declare -F phase_observe >/dev/null
declare -A PH_END=([peer_connect]=100)
PHASE_TTFP_US=1
PHASE_TARGET_HEIGHT=-1
# Suppress the unrelated RPC observations. The real cursor reader and caller
# still decide which phase boundaries to mark, with their real timestamps.
rpc() { return 0; }
phase_mark() { printf '%s %s %s\n' "$1" "$2" "$3" >> "$fixture/marks"; }
check() {
    : > "$fixture/marks"
    phase_observe 123 0 100 "$2"
    local actual
    actual=$(< "$fixture/marks")
    [[ $actual == "$1" ]] || {
        printf 'FAIL boundaries: expected <%s>, got <%s>\n' "$1" "$actual" >&2
        exit 1
    }
}
both='{"stage_cursors":[{"stage":"header_admit","cursor":101},{"stage":"body_persist","cursor":101}]}'
expected=$'headers start 123\nheaders end 123\nbodies end 123'
check "$expected" "$both"
check '' ''
check '' '{}'
check '' '{"stage":"header_admit","cursor":1},{"stage":"body_persist","cursor":1}'
check 'headers start 123' '{"stage":"header_admit","cursor":100},{"stage":"body_persist","cursor":100}'
check $'headers start 123\nheaders end 123' '{"stage":"header_admit","cursor":101}'
check 'bodies end 123' '{"stage":"body_persist","cursor":101}'
check 'bodies end 123' '{"stage":"header_admit","cursor":null},{"stage":"body_persist","cursor":101}'
check '' '{"stage":"header_admit_extra","cursor":101},{"stage":"body_persist","cursor_extra":101}'
check 'headers start 123' '{"stage":"header_admit","cursor":101},{"stage":"header_admit","cursor":2}'
check $'headers start 123\nheaders end 123' '{"stage":"header_admit","cursor":101},{"stage":"header_admit","cursor":null}'
check '' '{"stage": "header_admit","cursor":101}'
check '' $'{"stage":"header_admit",\n"cursor":101}'
check 'bodies end 123' $'{"stage":"header_admit","cursor":null},\n{"cursor":101,"stage":"body_persist"}'
check '' '{"stage":"header_admit","cursor":-1},{"stage":"body_persist","cursor":"101"}'
# This deliberately preserves the existing compact-record parser contract.
printf -v padding '%131072s' ''
check "$expected" "{\"padding\":\"$padding\",${both#\{}"
check "$expected" "${both%\}},\"padding\":\"$padding\"}"
printf 'phase observer boundary equivalence: PASS\n'
awk() { printf 'awk\n' >> "$fixture/calls"; command awk "$@"; }
tr() { printf 'tr\n' >> "$fixture/calls"; command tr "$@"; }
: > "$fixture/calls"
check "$expected" "$both"
calls=$(wc -l < "$fixture/calls")
unset -f awk tr
printf 'one phase observation: external cursor tools=%s\n' "$calls"
if (( bench )); then
    # Measure exactly the caller exercised above, with warm tools and files.
    TIMEFORMAT='500 phase observations: %3R s wall, %3U s user, %3S s system'
    time for ((i=0;i<500;i++)); do phase_observe 123 0 100 "$both"; done
fi
[[ $calls == 1 ]] || { echo 'FAIL: expected one cursor parser per phase observation' >&2; exit 1; }
pair_check() {
    local actual
    actual=$(frontier_stage_cursor "$2" "$3" "$4")
    [[ $actual == "$1" ]] || {
        printf 'FAIL cursor pair: expected <%s>, got <%s>\n' "$1" "$actual" >&2
        exit 1
    }
}
distinct='{"stage":"header_admit","cursor":4211},{"stage":"body_persist","cursor":77}'
pair_check '4211 77' "$distinct" header_admit body_persist
pair_check '77 4211' "$distinct" body_persist header_admit
pair_check '4211 4211' "$distinct" header_admit header_admit
pair_check '-1 77' "$distinct" missing body_persist
pair_check '4211 -1' "$distinct" header_admit missing
pair_check '-1 -1' '{}' header_admit body_persist
printf 'phase observer parser budget: PASS\n'
