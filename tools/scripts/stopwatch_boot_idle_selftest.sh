#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Hermetic boot-log observer regression; no node or network is used.
set -euo pipefail
export LC_ALL=C
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
fixture=$(mktemp -d /tmp/z23-boot-idle.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
. "$root/tools/scripts/stopwatch_json_lib.sh"
sed -n '/^boot_observation_from_log() {/,/^}/p; /^refresh_boot_observation() {/,/^}/p; /^is_self_respawn_reason() {/,/^}/p' \
    "$subject" > "$fixture/reader.sh"
. "$fixture/reader.sh"
DATADIR=$fixture boots=1 last_respawn_reason=prior
stat_fail=0 coarse=0 read_fail=0 append_after_scan=''
stat() {
    [[ $stat_fail == 0 ]] || return 1
    if [[ $coarse == 1 ]]; then
        [[ $1 == -f ]] || return 1
        printf '12 34 unavailable\n'
    else
        command stat "$@"
    fi
}
awk() {
    printf 'scan\n' >> "$fixture/scans"
    [[ $read_fail == 0 ]] || return 2
    local rc=0
    command awk "$@" || rc=$?
    if [[ -n $append_after_scan ]]; then
        printf '%s\n' "$append_after_scan" >> "$DATADIR/node.log"
    fi
    return "$rc"
}
check() {
    [[ $1 == "$2" ]] || {
        printf 'FAIL: %s: expected <%s>, got <%s>\n' "$3" "$1" "$2" >&2
        exit 1
    }
}
check_scans() { check "$1" "$(wc -l < "$fixture/scans")" "$2"; }
: > "$fixture/scans"
refresh_boot_observation
check '1 prior' "$boots $last_respawn_reason" 'missing log'
marker='exit-reason breadcrumb written: reason=self_respawn_both'
printf '[boot] prologue 1ms\n[boot] prologue 2ms\n%s\n' "$marker" > "$DATADIR/node.log"
refresh_boot_observation
check '2 self_respawn_both' "$boots $last_respawn_reason" 'first observation'
# Cached facts must still be applied when the caller has changed its state.
boots=1 last_respawn_reason=prior
refresh_boot_observation
check '2 self_respawn_both' "$boots $last_respawn_reason" 'cached observation'
printf '[boot] prologue 3ms\n' >> "$DATADIR/node.log"
refresh_boot_observation
check 3 "$boots" 'appended boot'
printf '%s\n' "$marker" > "$DATADIR/node.log"
refresh_boot_observation
check 3 "$boots" 'truncation preserves highest boot'
printf 'exit-reason breadcrumb written: reason=self_respawn_test\n' > "$fixture/replacement"
touch -r "$DATADIR/node.log" "$fixture/replacement"
mv "$fixture/replacement" "$DATADIR/node.log"
refresh_boot_observation
check self_respawn_test "$last_respawn_reason" 'same-size replacement with restored mtime'
touch -r "$DATADIR/node.log" "$fixture/mtime"
sleep 0.02
printf '%s\n' "$marker" > "$DATADIR/node.log"
touch -r "$fixture/mtime" "$DATADIR/node.log"
refresh_boot_observation
check self_respawn_both "$last_respawn_reason" 'same-inode rewrite with restored mtime'

printf 'new diagnostic\n' > "$DATADIR/node.log"
append_after_scan='exit-reason breadcrumb written: reason=self_respawn_after'
refresh_boot_observation
append_after_scan=''
refresh_boot_observation
check self_respawn_after "$last_respawn_reason" 'append during scan is visible next poll'
printf '%s\n' "$marker" > "$DATADIR/node.log"
read_fail=1
refresh_boot_observation
read_fail=0
refresh_boot_observation
check self_respawn_both "$last_respawn_reason" 'failed scan is retried'
for failure in stat_fail coarse; do
    printf -v "$failure" 1
    : > "$fixture/scans"
    refresh_boot_observation
    refresh_boot_observation
    check_scans 2 'unusable metadata never suppresses scans'
    printf -v "$failure" 0
done
mv "$DATADIR/node.log" "$fixture/target"
ln -s "$fixture/target" "$DATADIR/node.log"
: > "$fixture/scans"
refresh_boot_observation
printf 'exit-reason breadcrumb written: reason=self_respawn_link\n' >> "$fixture/target"
refresh_boot_observation
check self_respawn_link "$last_respawn_reason" 'symlink target append'
check_scans 2 'linked logs always scanned'
rm "$DATADIR/node.log"
command awk 'BEGIN { for (i=0;i<262144;i++) printf "%063d\n", i }' > "$DATADIR/node.log"
printf '[boot] prologue 1ms\n%s\n' "$marker" >> "$DATADIR/node.log"
for trial in 1 2 3; do
    boot_log_signature=''
    : > "$fixture/scans"
    TIMEFORMAT="trial=$trial polls=20 log_mib=16 wall=%3R user=%3U sys=%3S"
    time for ((i=0;i<20;i++)); do refresh_boot_observation; done
    printf 'trial=%s full_log_scans=%s\n' "$trial" "$(wc -l < "$fixture/scans")"
    if (( ! baseline )); then check_scans 1 'unchanged log scan budget'; fi
done
: > "$fixture/scans"
for ((i=0;i<20;i++)); do
    printf 'new diagnostic\n' >> "$DATADIR/node.log"
    refresh_boot_observation
done
check_scans 20 'growing log remains observable every poll'
check self_respawn_both "$last_respawn_reason" 'benchmark observation'
printf 'PASS: boot-log cache invalidation, failures, observations and scan budget\n'
