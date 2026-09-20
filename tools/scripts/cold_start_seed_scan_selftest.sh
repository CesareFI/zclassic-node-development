#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the real seed-readiness observer without starting a node.
# Usage: bash tools/scripts/cold_start_seed_scan_selftest.sh [--bench] [probe]
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}
fixture=$(mktemp -d /tmp/z23-seed-scan.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Load just constants and the observer, never the harness's live dispatch.
sed -n '/^BUNDLE_SUCCESS_PATTERN=/p; /^CONSENSUS_BUNDLE_.*PATTERN=/p; /^CONSENSUS_BUNDLE_MARKER=/p; /^probe_file_metadata() {/,/^}/p; /^note_seed_ready() {/,/^}/p' \
    "$subject" > "$fixture/functions.sh"
. "$root/tools/scripts/stopwatch_json_lib.sh"
# shellcheck source=/dev/null
. "$fixture/functions.sh"
declare -F note_seed_ready >/dev/null
DATADIR=$fixture
mark_seeded() { seeded=1; marks=$((marks + 1)); }
grep() {
    printf 'scan\n' >> "$fixture/scans"
    command grep "$@"
}
check() {
    [[ $2 == "$3" ]] || {
        printf 'FAIL: %s: expected <%s>, got <%s>\n' "$1" "$2" "$3" >&2
        exit 1
    }
}
observe() {
    seeded=0 marks=0
    note_seed_ready > "$fixture/output"
    check "$1 readiness" "$2" "$seeded"
    check "$1 mark count" "$2" "$marks"
    if [[ $2 == 1 ]]; then
        note_seed_ready >> "$fixture/output"
        check "$1 marked only once" 1 "$marks"
    fi
}
MODE=consensus-state-bundle
observe 'missing log' 0
: > "$DATADIR/probe.log"
observe 'empty log' 0
printf '%s\n' 'ordinary startup, still downloading' > "$DATADIR/probe.log"
observe 'no markers' 0
printf '%s\n' 'prefix autodetected consensus bundle installed suffix' > "$DATADIR/probe.log"
observe 'installed marker' 1
check 'installed diagnostic' 'c3-probe: seed authority ready — consensus-state-bundle installed' "$(cat "$fixture/output")"
printf '%s\n' 'prefix install-on-next-boot request installed suffix' > "$DATADIR/probe.log"
observe 'request marker' 1
printf 'binary\0prefix install-on-next-boot request installed' > "$DATADIR/probe.log"
observe 'binary log and unterminated last line' 1
printf 'install-on-next-boot request' > "$DATADIR/probe.log"
observe 'partial marker' 0
printf ' installed' >> "$DATADIR/probe.log"
observe 'completed append' 1
: > "$DATADIR/probe.log"
observe 'truncated log' 0
rm "$DATADIR/probe.log"
: > "$DATADIR/$CONSENSUS_BUNDLE_MARKER"
: > "$fixture/scans"
observe 'marker file without log' 1
check 'marker file skips log' 0 "$(wc -l < "$fixture/scans")"
rm "$DATADIR/$CONSENSUS_BUNDLE_MARKER"
MODE=operator-bundle
printf '%s\n' 'autodetected consensus bundle installed' > "$DATADIR/probe.log"
observe 'operator mode ignores consensus marker' 0
printf '%s\n' '-load-snapshot-at-own-height: coin set RE-SEEDED count=1000001' >> "$DATADIR/probe.log"
observe 'operator seed marker' 1
check 'operator diagnostic' 'c3-probe: seed authority ready — -load-snapshot-at-own-height: coin set RE-SEEDED count=1000001' "$(cat "$fixture/output")"
MODE=legacy-snapshot
observe 'legacy mode unchanged' 0
MODE=consensus-state-bundle
: > "$DATADIR/probe.log"
: > "$fixture/scans"
observe 'pending bundle scan budget' 0
scans=$(wc -l < "$fixture/scans")
printf 'pending bundle: log scans per poll=%s (baseline: 2)\n' "$scans"
seeded=1
: > "$fixture/scans"
note_seed_ready >/dev/null
check 'already seeded skips log' 0 "$(wc -l < "$fixture/scans")"
if (( bench )); then
    # Exactly 16 MiB of warm newline-delimited logs without a ready marker.
    awk 'BEGIN { for (i=0;i<262144;i++) printf "%063d\n", i }' > "$DATADIR/probe.log"
    seeded=0 marks=0
    TIMEFORMAT='20 pending polls, 16 MiB log: %3R s wall, %3U s user, %3S s system'
    time for ((i=0;i<20;i++)); do note_seed_ready >/dev/null; done
    check 'benchmark remains pending' 0 "$seeded"
fi
check 'one scan per pending poll' 1 "$scans"
printf 'cold-start seed scan: PASS\n'
