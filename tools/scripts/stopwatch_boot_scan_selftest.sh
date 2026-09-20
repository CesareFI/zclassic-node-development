#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise only the stopwatch's log observer; never launch a node.
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
if [[ "${1:-}" == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
fixture=$(mktemp -d /tmp/z23-boot-scan.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
# Extract complete production functions, without executing the harness setup.
sed -n '/^# boot_.* <node.log>/,/^# bytes_delta_compute /p' "$subject" > "$fixture/functions.sh"
sed -n '/^is_self_respawn_reason() {/,/^}/p' "$subject" >> "$fixture/functions.sh"
. "$fixture/functions.sh"
DATADIR=$fixture
calls=$fixture/calls
scans=$fixture/scans
observe_tool() {
    local tool=$1 arg
    shift
    printf '%s\n' "$tool" >> "$calls"
    for arg in "$@"; do
        [[ "$arg" != "$DATADIR/node.log" ]] || printf 'scan\n' >> "$scans"
    done
    command "$tool" "$@"
}
awk() { observe_tool awk "$@"; }
sed() { observe_tool sed "$@"; }
tail() { observe_tool tail "$@"; }
check() {
    [[ "$2" == "$3" ]] || {
        printf 'FAIL: %s: expected <%s>, got <%s>\n' "$1" "$2" "$3" >&2
        exit 1
    }
}
boots=1 last_respawn_reason=prior
refresh_boot_observation
check 'missing log preserves observations' '1 prior' "$boots $last_respawn_reason"
: > "$DATADIR/node.log"
refresh_boot_observation
check 'empty log preserves observations' '1 prior' "$boots $last_respawn_reason"
cat > "$DATADIR/node.log" <<'LOG'
[boot] prologue 12ms
[boot]   prologue 3ms
[boot] prologue took 9ms today
prefix [boot] prologue 4ms
[boot] prologue 1ms extra
[boot] prologue 8ms
exit-reason breadcrumb written: reason=self_respawn_tip_watchdog
LOG
refresh_boot_observation
check 'exact markers and allowed reason' '2 self_respawn_tip_watchdog' "$boots $last_respawn_reason"
for reason in self_respawn_supervisor_backstop self_respawn_both; do
    printf 'prefix exit-reason breadcrumb written: reason=%s\n' "$reason" >> "$DATADIR/node.log"
    refresh_boot_observation
    check 'latest known reason' "$reason" "$last_respawn_reason"
done
# Preserve the existing classifier's acceptance of any self_respawn_ suffix.
printf 'exit-reason breadcrumb written: reason=self_respawn_future\n' >> "$DATADIR/node.log"
last_respawn_reason=prior
refresh_boot_observation
check 'future respawn suffix remains observable' '2 self_respawn_future' "$boots $last_respawn_reason"
printf '[boot] prologue\t20ms\n' >> "$DATADIR/node.log"
refresh_boot_observation
check 'append detects another boot' 3 "$boots"
printf '[boot] prologue 1ms\n' > "$DATADIR/node.log"
refresh_boot_observation
check 'truncation cannot lower observed boots' 3 "$boots"
# Match the old greedy breadcrumb extraction and unterminated final line.
printf 'exit-reason breadcrumb written: reason=self_respawn_both exit-reason breadcrumb written: reason=self_respawn_tip_watchdog' > "$DATADIR/node.log"
refresh_boot_observation
check 'last marker on an unterminated line' self_respawn_tip_watchdog "$last_respawn_reason"
printf 'exit-reason breadcrumb written: reason=self_respawn_both \n' > "$DATADIR/node.log"
refresh_boot_observation
check 'trailing whitespace is not an exact breadcrumb' self_respawn_tip_watchdog "$last_respawn_reason"
: > "$calls"; : > "$scans"
refresh_boot_observation
tool_count=$(wc -l < "$calls")
scan_count=$(wc -l < "$scans")
printf 'one observation: tools=%s log_scans=%s\n' "$tool_count" "$scan_count"
if [[ "$bench" == 1 ]]; then
    # 16 MiB of ordinary newline-delimited log text, warm filesystem cache.
    command awk 'BEGIN { for (i=0;i<262144;i++) printf "%063d\n", i }' > "$DATADIR/node.log"
    printf '[boot] prologue 12ms\nexit-reason breadcrumb written: reason=self_respawn_both\n' >> "$DATADIR/node.log"
    TIMEFORMAT='20 observations, 16 MiB log: %3R s wall, %3U s user, %3S s system'
    time for ((i=0;i<20;i++)); do refresh_boot_observation; done
    check 'benchmark reason' self_respawn_both "$last_respawn_reason"
fi
check 'single tool per observation' 1 "$tool_count"
check 'single log scan per observation' 1 "$scan_count"
printf 'stopwatch boot scan: PASS\n'
