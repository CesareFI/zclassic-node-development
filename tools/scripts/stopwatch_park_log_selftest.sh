#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic named-park observer regression and optional process-cost benchmark.
set -euo pipefail
export LC_ALL=C
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
. "$root/tools/scripts/stopwatch_json_lib.sh"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/zcl-park-log.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
sed -n '/^log_named_park() {/,/^}/p' "$subject" > "$scratch/reader.sh"
. "$scratch/reader.sh"
declare -F log_named_park >/dev/null
DATADIR=$scratch
reference_park() {
    grep -aoE "PARKED alive-degraded at gate '[^']*'" "$DATADIR/node.log" 2>/dev/null |
        tail -1 | sed -E "s/.*gate '([^']*)'.*/\1/"
}
check() {
    local label=$1 expected=$2 status=$3 actual reference rc=0 ref_rc=0
    actual=stale
    log_named_park actual || rc=$?
    reference=$(reference_park) || ref_rc=$?
    if [[ $actual != "$expected" || $rc != "$status" ||
          $actual != "$reference" || $rc != "$ref_rc" ]]; then
        printf 'FAIL: %s: expected <%s> rc=%s; got <%s> rc=%s; reference <%s> rc=%s\n' \
            "$label" "$expected" "$status" "$actual" "$rc" "$reference" "$ref_rc" >&2
        exit 1
    fi
}
check missing '' 2
: > "$DATADIR/node.log"
check empty '' 1
printf 'ordinary boot progress\n' > "$DATADIR/node.log"
check no-marker '' 1
printf "[boot] PARKED alive-degraded at gate 'params_missing' waiting\n" > "$DATADIR/node.log"
check one-marker params_missing 0
printf "PARKED alive-degraded at gate 'last_gate' waiting\n" >> "$DATADIR/node.log"
check latest-marker last_gate 0
printf "PARKED alive-degraded at gate 'first' PARKED alive-degraded at gate 'second'" > "$DATADIR/node.log"
check same-line-unterminated second 0
printf "PARKED alive-degraded at gate ''\n" > "$DATADIR/node.log"
check empty-name '' 0
printf "PARKED alive-degraded at gate 'spaces and \\slashes' suffix\r\n" > "$DATADIR/node.log"
check literal-name 'spaces and \slashes' 0
printf "PARKED alive-degraded at gate 'valid'\nPARKED alive-degraded at gate 'unfinished" > "$DATADIR/node.log"
check incomplete-latest valid 0
# A large stream exercises tail's full drain under pipefail. Binary bytes
# outside the marker must not suppress grep's text-mode observation.
awk 'BEGIN { for (i=0; i<10000; i++) print "PARKED alive-degraded at gate '\''old'\''" }' > "$DATADIR/node.log"
printf "\000PARKED alive-degraded at gate 'final'\n" >> "$DATADIR/node.log"
check large-binary-log final 0

if [[ $bench == 1 ]]; then
    printf "[boot] PARKED alive-degraded at gate 'params_missing' waiting\n" > "$DATADIR/node.log"
    TIMEFORMAT='1000 named-park observations: %3R s wall, %3U s user, %3S s system'
    printf 'reference: '
    time for ((i=0; i<1000; i++)); do observed=$(reference_park); done
    printf 'changed: '
    time for ((i=0; i<1000; i++)); do log_named_park observed; done
fi

# Count real external tool invocations independently of noisy wall timings.
expected_tools=1
metadata=$(stopwatch_file_metadata "$DATADIR/node.log") || metadata=' unavailable'
case "$metadata" in *' unavailable') expected_tools=4 ;; esac
observe() { printf '%s\n' "$1" >> "$scratch/tools"; command "$@"; }
grep() { observe grep "$@"; }
tail() { observe tail "$@"; }
sed() { observe sed "$@"; }
awk() { observe awk "$@"; }
stat() { observe stat "$@"; }
log_named_park observed
count=$(wc -l < "$scratch/tools")
printf 'named-park observer: %s external tools per observation\n' "$count"
[[ $count == "$expected_tools" ]] || { echo 'FAIL: unchanged log process budget' >&2; exit 1; }
echo 'stopwatch park log: PASS (10 compatibility cases and process budget)'
