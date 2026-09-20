#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the real boundary snapshot writer using only local fixture data.
# Usage: bash tools/scripts/stopwatch_phase_profile_selftest.sh [--bench] [subject]
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
fixture=$(mktemp -d /tmp/z23-phase-profile.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
sed -n '/^rsp_cum() {/,/^}/p; /^phase_profile_snapshot() {/,/^}/p' \
    "$subject" > "$fixture/observer.sh"
. "$fixture/observer.sh"
declare -F rsp_cum >/dev/null
declare -F phase_profile_snapshot >/dev/null
. "$root/tools/scripts/stopwatch_json_lib.sh"
rpc() {
    [[ $* == 'dumpstate reducer_stage_profile' ]]
    printf 'rpc\n' >> "$fixture/rpcs"
    printf '%s' "$reply"
}
PHASE_PROFILE_DIR=$fixture
PHASE_PROFILE_INDEX_ROWS=''
PID=$$
check() {
    local expected=$1 actual
    reply=$2
    PHASE_PROFILE_INDEX_ROWS=''
    : > "$fixture/rpcs"
    phase_profile_snapshot headers.end 123
    actual=$(< "$fixture/headers.end.json")
    [[ $actual == "$reply" ]]
    [[ $(< "$fixture/rpcs") == rpc ]]
    [[ $PHASE_PROFILE_INDEX_ROWS == '{"at":"headers.end","unix_s":123,"snapshot":"headers.end.json",'"$expected"'}' ]] || {
        printf 'FAIL snapshot row: %s\n' "$PHASE_PROFILE_INDEX_ROWS" >&2
        exit 1
    }
}
good='{"body_persist":{"cumulative":{"total_us":9910222,"blocks":812},"last_batch":{"total_us":74,"blocks":64}},"script_validate":{"cumulative":{"total_us":555},"last_batch":{"total_us":123}}}'
values='"body_persist_cumulative_total_us":9910222,"body_persist_cumulative_blocks":812,"script_validate_cumulative_total_us":555'
missing='"body_persist_cumulative_total_us":-1,"body_persist_cumulative_blocks":-1,"script_validate_cumulative_total_us":-1'
check "$values" "$good"
check "$missing" '{}'
check "$missing" '{"body_persist":{"cumulative":{"total_us":null,"blocks":null},"last_batch":{"total_us":74,"blocks":64}},"script_validate":{"cumulative":{"total_us":null},"last_batch":{"total_us":123}}}'
check '"body_persist_cumulative_total_us":0,"body_persist_cumulative_blocks":0,"script_validate_cumulative_total_us":-1' \
    '{"body_persist":{"cumulative":{"blocks":0,"total_us":0},"last_batch":{"total_us":74}},"script_validate":{"last_batch":{"total_us":123}}}'
check '"body_persist_cumulative_total_us":-1,"body_persist_cumulative_blocks":-1,"script_validate_cumulative_total_us":555' \
    '{"script_validate":{"cumulative":{"total_us":555},"last_batch":{"total_us":123}}}'
# Preserve the compact first-line reader contract, including large responses.
printf -v padding '%131072s' ''
check "$values" "{\"padding\":\"$padding\",${good#\{}"
check "$values" "${good%\}},\"padding\":\"$padding\"}"
check "$values" "$good"$'\n{}'
check "$missing" $'{}\n'"$good"
reply=$good
PHASE_PROFILE_INDEX_ROWS=''
phase_profile_snapshot headers.start 120
first=$PHASE_PROFILE_INDEX_ROWS
phase_profile_snapshot headers.end 123
[[ $PHASE_PROFILE_INDEX_ROWS == "$first,"* ]]
reply=''
phase_profile_snapshot absent 124
[[ ! -e $fixture/absent.json ]]
PID=''
reply=$good
phase_profile_snapshot no_pid 124
[[ ! -e $fixture/no_pid.json ]]
printf 'boundary snapshot values, raw evidence, and missing observations: PASS\n'
PID=$$
awk() { printf 'awk\n' >> "$fixture/calls"; command awk "$@"; }
: > "$fixture/calls"
check "$values" "$good"
calls=$(wc -l < "$fixture/calls")
unset -f awk
printf 'one boundary snapshot: external parsers=%s\n' "$calls"
if (( bench )); then
    TIMEFORMAT='200 boundary snapshots: %3R s wall, %3U s user, %3S s system'
    time for ((i=0;i<200;i++)); do
        PHASE_PROFILE_INDEX_ROWS=''
        phase_profile_snapshot headers.end 123
    done
fi
[[ $calls == 1 ]] || { echo 'FAIL: expected one parser per boundary snapshot' >&2; exit 1; }
printf 'boundary snapshot parser budget: PASS\n'
