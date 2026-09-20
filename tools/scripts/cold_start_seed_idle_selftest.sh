#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure repeated seed-log observations using isolated files, never a node.
# Usage: bash tools/scripts/cold_start_seed_idle_selftest.sh [--baseline] [probe]
set -euo pipefail
export LC_ALL=C
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}
. "$root/tools/scripts/stopwatch_json_lib.sh"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/z23-seed-idle.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n '/^BUNDLE_SUCCESS_PATTERN=/p; /^CONSENSUS_BUNDLE_.*PATTERN=/p; /^CONSENSUS_BUNDLE_MARKER=/p; /^probe_file_metadata() {/,/^}/p; /^note_seed_ready() {/,/^}/p' \
    "$subject" > "$fixture/functions.sh"
# shellcheck source=/dev/null
. "$fixture/functions.sh"
declare -F note_seed_ready >/dev/null
DATADIR=$fixture
stat_fail=0 stat_bsd=0 grep_fail=0 marks=0 seeded=0 append_after_scan=''
mark_seeded() { seeded=1; marks=$((marks + 1)); }
stat() {
    [[ $stat_fail == 0 ]] || return 1
    if [[ $stat_bsd == 1 ]]; then
        [[ $1 == -f && $2 == '%z %m unavailable' ]] || return 1
        printf '12 34 unavailable\n'
        return 0
    fi
    command stat "$@"
}
grep() {
    printf 'scan\n' >> "$fixture/scans"
    [[ $grep_fail == 0 ]] || return 2
    local result=0
    command grep "$@" || result=$?
    if [[ -n $append_after_scan ]]; then
        printf '%s' "$append_after_scan" >> "$DATADIR/probe.log"
    fi
    return "$result"
}
check() {
    [[ $2 == "$3" ]] || {
        printf 'FAIL: %s: expected <%s>, got <%s>\n' "$1" "$2" "$3" >&2
        exit 1
    }
}
pending() {
    note_seed_ready > "$fixture/output"
    check "$1 remains pending" 0 "$seeded"
}
ready() {
    note_seed_ready > "$fixture/output"
    check "$1 ready" 1 "$seeded"
    check "$1 marked once" 1 "$marks"
    note_seed_ready >> "$fixture/output"
    check "$1 stays marked once" 1 "$marks"
    seeded=0 marks=0
}
for MODE in operator-bundle consensus-state-bundle; do
    if [[ $MODE == operator-bundle ]]; then
        marker=$BUNDLE_SUCCESS_PATTERN
    else
        marker=$CONSENSUS_BUNDLE_SUCCESS_PATTERN
    fi
    rm -f "$DATADIR/probe.log"
    seed_log_signature=''
    pending 'missing log'
    printf 'startup pending\n' > "$DATADIR/probe.log"
    : > "$fixture/scans"
    for ((i=0; i<20; i++)); do pending 'quiet log'; done
    scans=$(wc -l < "$fixture/scans")
    printf 'mode=%s quiet_polls=20 log_scans=%s\n' "$MODE" "$scans"
    if (( ! baseline )); then check 'quiet-log scan budget' 1 "$scans"; fi
    printf '%s' "${marker:0:10}" >> "$DATADIR/probe.log"
    pending 'partial append'
    printf '%s' "${marker:10}" >> "$DATADIR/probe.log"
    ready 'completed append without newline'
    : > "$DATADIR/probe.log"
    pending 'truncation'
    printf 'binary\0%s\n' "$marker" >> "$DATADIR/probe.log"
    ready 'binary log append'

    # Same size and restored mtime must not hide replacement or overwrite.
    printf '%*s' "${#marker}" '' > "$DATADIR/probe.log"
    pending 'before replacement'
    printf '%s' "$marker" > "$fixture/replacement"
    touch -r "$DATADIR/probe.log" "$fixture/replacement"
    mv "$fixture/replacement" "$DATADIR/probe.log"
    ready 'same-size replacement with identical mtime'
    printf '%*s' "${#marker}" '' > "$DATADIR/probe.log"
    pending 'before overwrite'
    touch -r "$DATADIR/probe.log" "$fixture/mtime"
    sleep 0.02
    printf '%s' "$marker" > "$DATADIR/probe.log"
    touch -r "$fixture/mtime" "$DATADIR/probe.log"
    ready 'same-inode overwrite with restored mtime'

    printf 'pending\n' > "$DATADIR/probe.log"
    pending 'before metadata failure'
    stat_fail=1
    : > "$fixture/scans"
    pending 'metadata failure first poll'
    pending 'metadata failure second poll'
    check 'metadata failure cannot suppress scans' 2 "$(wc -l < "$fixture/scans")"
    stat_fail=0
    stat_bsd=1
    : > "$fixture/scans"
    pending 'BSD metadata first poll'
    pending 'BSD metadata second poll'
    check 'coarse timestamps cannot suppress scans' 2 "$(wc -l < "$fixture/scans")"
    if declare -F probe_file_metadata >/dev/null; then
        check 'BSD fallback retains fixture fields' '12 34 unavailable' "$(probe_file_metadata "$DATADIR/probe.log")"
    fi
    stat_bsd=0
    printf '%s\n' "$marker" > "$DATADIR/probe.log"
    grep_fail=1
    pending 'reader failure'
    grep_fail=0
    ready 'reader failure retries unchanged file'

    printf 'pending\n' > "$DATADIR/probe.log"
    append_after_scan=$marker
    pending 'append immediately after reader misses'
    append_after_scan=''
    ready 'concurrent append observed next poll'

    printf 'pending\n' > "$fixture/linked.log"
    rm "$DATADIR/probe.log"
    ln -s "$fixture/linked.log" "$DATADIR/probe.log"
    pending 'linked log'
    printf '%s' "$marker" >> "$fixture/linked.log"
    ready 'linked log target append'
done

# The independent install marker and mode change must bypass a prior miss.
rm "$DATADIR/probe.log"
MODE=operator-bundle
printf '%s\n' "$CONSENSUS_BUNDLE_REQUEST_PATTERN" > "$DATADIR/probe.log"
pending 'other mode marker'
MODE=consensus-state-bundle
ready 'mode changed on same log'
printf 'pending\n' > "$DATADIR/probe.log"
pending 'before install marker'
: > "$DATADIR/$CONSENSUS_BUNDLE_MARKER"
: > "$fixture/scans"
ready 'install marker appears on quiet log'
check 'install marker skips log reader' 0 "$(wc -l < "$fixture/scans")"
rm "$DATADIR/$CONSENSUS_BUNDLE_MARKER"

# Exactly 16 MiB, no marker, ordinary warm filesystem cache. Gate scan count;
# wall time is descriptive and includes the metadata observations.
awk 'BEGIN { for (i=0;i<262144;i++) printf "%063d\n", i }' > "$DATADIR/probe.log"
for ((trial=1; trial<=3; trial++)); do
    seed_log_signature=''
    : > "$fixture/scans"
    TIMEFORMAT="trial=$trial polls=20 log_mib=16 wall_seconds=%3R"
    time for ((i=0; i<20; i++)); do pending 'benchmark'; done
    scans=$(wc -l < "$fixture/scans")
    printf 'trial=%d full_log_scans=%s\n' "$trial" "$scans"
    if (( ! baseline )); then check 'benchmark scan budget' 1 "$scans"; fi
done
seed_log_signature=''
: > "$fixture/scans"
TIMEFORMAT='growing_log polls=20 log_mib=16 wall_seconds=%3R'
time for ((i=0; i<20; i++)); do
    printf 'appended diagnostic\n' >> "$DATADIR/probe.log"
    pending 'growing benchmark'
done
check 'growing log must be rescanned every poll' 20 "$(wc -l < "$fixture/scans")"
printf 'PASS: quiet log, append, truncation, replacement, rewrite, modes and failure retries\n'
