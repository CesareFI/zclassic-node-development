#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic overlap-report regression and optional observer-cost benchmark.
# Usage: bash tools/scripts/stopwatch_overlap_selftest.sh [--bench] [subject]
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject=${1:-$script_dir/cold_start_to_tip_stopwatch.sh}
fixture=$(mktemp -d /tmp/z23-stopwatch-overlap.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n '/^phase_span_ms() {/,/^}/p; /^phase_overlap_json() {/,/^}/p' \
    "$subject" > "$fixture/observer.sh"
. "$fixture/observer.sh"
declare -F phase_span_ms >/dev/null
declare -F phase_overlap_json >/dev/null
declare -A PH_START=() PH_END=()
PHASE_NAMES='peer_connect headers bodies fold'
LOOP_START_UNIX=1000
set_phases() {
    local p
    for p in $PHASE_NAMES; do
        PH_START[$p]=$1; PH_END[$p]=$2; shift 2
    done
}
expect() {
    [[ $actual == *"$1"* ]] || {
        printf 'FAIL: missing %s in %s\n' "$1" "$actual" >&2
        exit 1
    }
}
set_phases 1000 1010 1010 1100 1050 1500 1060 1520
actual=$(phase_overlap_json 1600)
expect '"observed_phase_count":4'
expect '"sum_of_observed_phase_ms":1010000'
expect '"union_of_observed_phase_ms":520000'
expect '"double_counted_ms":490000'
expect '"window_ms_covered_by_no_phase":80000'
expect '"sync.bodies|sync.fold":440000'
set_phases -1 -1 -1 -1 -1 -1 -1 -1
actual=$(phase_overlap_json 1600)
expect '"observed_phase_count":0'
expect '"sum_of_observed_phase_ms":null'
expect '"union_of_observed_phase_ms":null'
expect '"sync.bodies|sync.fold":null'
# Instant, reversed, half-observed and disjoint intervals remain distinct.
set_phases 1000 1000 1020 1010 1030 -1 1100 1110
actual=$(phase_overlap_json 1600)
expect '"observed_phase_count":2'
expect '"sum_of_observed_phase_ms":10000'
expect '"union_of_observed_phase_ms":10000'
expect '"sync.fold|sync.peer_connect":0'
expect '"sync.headers|sync.peer_connect":null'
printf 'overlap values and repeated report freshness: PASS\n'

set_phases 1000 1010 1010 1100 1050 1500 1060 1520
if (( bench )); then
    TIMEFORMAT='200 overlap reports: %3R s wall, %3U s user, %3S s system'
    time for ((i=0; i<200; i++)); do phase_overlap_json 1600 >/dev/null; done
fi
# Count real function invocations across command substitutions. Retain the
# actual implementation so the budget cannot pass by stubbing out its work.
sed 's/^phase_span_ms()/measured_phase_span_ms()/' "$fixture/observer.sh" > "$fixture/measured.sh"
. "$fixture/measured.sh"
phase_span_ms() {
    printf '%s\n' "$1" >> "$fixture/calls"
    measured_phase_span_ms "$@"
}
: > "$fixture/calls"
phase_overlap_json 1600 >/dev/null
calls=$(wc -l < "$fixture/calls")
printf 'one four-phase report: span subprocesses=%s\n' "$calls"
[[ $calls == 4 ]] || { echo 'FAIL: expected one span evaluation per phase' >&2; exit 1; }
printf 'overlap evaluation budget: PASS\n'
