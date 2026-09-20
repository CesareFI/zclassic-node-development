#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Isolated cold-start log observer regression; never launches a node.
# Usage: bash tools/scripts/cold_start_log_idle_selftest.sh [--baseline] [source]
set -euo pipefail
export LC_ALL=C
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_test.sh}
fixture=$(mktemp -d /tmp/z23-coldstart-log.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
. "$root/tools/scripts/stopwatch_json_lib.sh"
sed -n '/^cold_start_log_hit() {/,/^}/p' "$subject" > "$fixture/reader.sh"
if [[ ! -s $fixture/reader.sh ]]; then
    # Exercise the actual previous loop expression, without running the gate.
    printf 'cold_start_log_hit() {\n' > "$fixture/reader.sh"
    sed -n '/^    hit=$(grep /p' "$subject" >> "$fixture/reader.sh"
    printf '}\n' >> "$fixture/reader.sh"
fi
. "$fixture/reader.sh"
LOG=$fixture/node.log
want_pattern='snapshot-first import OK: '
marker='[boot] snapshot-first import OK: 1234567 UTXOs at h=42'
log_miss_signature='' hit=''
stat_fail=0 grep_fail=0 coarse=0 append_after_scan=''
stat() {
    [[ $stat_fail == 0 ]] || return 1
    if [[ $coarse == 1 ]]; then
        [[ $1 == -f ]] || return 1
        printf '12 34 unavailable\n'
    else
        command stat "$@"
    fi
}
grep() {
    printf 'scan\n' >> "$fixture/scans"
    [[ $grep_fail == 0 ]] || return 2
    local rc=0
    command grep "$@" || rc=$?
    if [[ -n $append_after_scan ]]; then
        printf '%s\n' "$append_after_scan" >> "$LOG"
    fi
    return "$rc"
}
check() { [[ $1 == "$2" ]] || { printf 'FAIL: %s: expected <%s>, got <%s>\n' "$3" "$1" "$2" >&2; exit 1; }; }
pending() { cold_start_log_hit; check '' "$hit" "$1"; }
ready() { cold_start_log_hit; check "$marker" "$hit" "$1"; }
: > "$fixture/scans"
pending 'missing file'
printf 'waiting\n' > "$LOG"
pending 'no marker'
printf '%s' "${marker:0:20}" >> "$LOG"
pending 'split marker'
printf '%s' "${marker:20}" >> "$LOG"
ready 'append without newline'
: > "$LOG"
pending 'truncation'
printf 'binary\0prefix\n%s\n' "$marker" >> "$LOG"
ready 'binary log'
printf '%*s' "${#marker}" '' > "$LOG"
pending 'before replacement'
printf '%s' "$marker" > "$fixture/replacement"
touch -r "$LOG" "$fixture/replacement"
mv "$fixture/replacement" "$LOG"
ready 'same-size replacement with restored mtime'
printf '%*s' "${#marker}" '' > "$LOG"
pending 'before same-inode rewrite'
touch -r "$LOG" "$fixture/mtime"
sleep 0.02
printf '%s' "$marker" > "$LOG"
touch -r "$fixture/mtime" "$LOG"
ready 'same-inode rewrite with restored mtime'
grep_fail=1
pending 'reader error'
grep_fail=0
ready 'retry reader error'
printf 'waiting\n' > "$LOG"
append_after_scan=$marker
pending 'append after failed search'
append_after_scan=''
ready 'next poll observes concurrent append'
printf 'waiting\n' > "$LOG"
pending 'before mode change'
want_pattern='waiting'
marker='waiting'
ready 'mode change invalidates miss'
want_pattern='snapshot-first import OK: '
for failure in stat_fail coarse; do
    printf -v "$failure" 1
    : > "$fixture/scans"
    pending 'unusable metadata first poll'
    pending 'unusable metadata second poll'
    check 2 "$(wc -l < "$fixture/scans")" 'unusable metadata cannot suppress reads'
    printf -v "$failure" 0
done
mv "$LOG" "$fixture/linked.log"
ln -s "$fixture/linked.log" "$LOG"
pending 'linked log before append'
marker='[boot] snapshot-first import OK: 1234567 UTXOs at h=42'
printf '%s\n' "$marker" >> "$fixture/linked.log"
ready 'linked target append'
rm "$LOG"
want_pattern='-load-snapshot-at-own-height: coin set RE-SEEDED'
marker="$want_pattern count=1234567"
printf '%s\n' "$marker" > "$LOG"
ready 'operator bundle literal begins with dash'
want_pattern='snapshot-first import OK: '

# Same warmed 16 MiB absent-marker fixture for baseline and candidate.
awk 'BEGIN { for(i=0;i<262144;i++) printf "%063d\n", i }' > "$LOG"
for trial in 1 2 3; do
    log_miss_signature=''
    : > "$fixture/scans"
    TIMEFORMAT="trial=$trial polls=20 log_mib=16 wall_seconds=%3R"
    time for ((i=0;i<20;i++)); do pending 'quiet log'; done
    scans=$(wc -l < "$fixture/scans")
    printf 'trial=%s full_log_scans=%s\n' "$trial" "$scans"
    if (( ! baseline )); then check 1 "$scans" 'quiet-log scan budget'; fi
done
: > "$fixture/scans"
for ((i=0;i<20;i++)); do
    printf 'new diagnostic\n' >> "$LOG"
    pending 'growing log'
done
check 20 "$(wc -l < "$fixture/scans")" 'growing log must be searched each poll'
printf 'PASS: cold-start log values, invalidation, read failures and scan budget\n'
