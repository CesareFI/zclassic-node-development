#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic resource-observer regression; --bench also measures 500 samples.
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
fixture=$(mktemp -d /tmp/z23-proc-stat.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
sed -n '/^parse_proc_stat_counters() {/,/^}/p; /^parse_proc_stat_cpu_ticks() {/,/^}/p; /^parse_proc_stat_rss_pages() {/,/^}/p; /^parse_proc_io_field() {/,/^}/p; /^refresh_process_counters() {/,/^}/p' \
    "$subject" > "$fixture/reader.sh"
. "$fixture/reader.sh"
# The optional old-source argument runs the same fixture and benchmark against
# an older implementation. It must fail the final zero-parser budget.
if ! declare -F parse_proc_stat_counters >/dev/null; then
    declare -F parse_proc_stat_cpu_ticks >/dev/null
    declare -F parse_proc_stat_rss_pages >/dev/null
    parse_proc_stat_counters() {
        local cpu rss
        cpu=$(parse_proc_stat_cpu_ticks "$1")
        rss=$(parse_proc_stat_rss_pages "$1")
        printf '%s %s\n' "$cpu" "$rss"
    }
fi
check() {
    local actual
    actual=$(parse_proc_stat_counters "$2")
    [[ $actual == "$1" ]] || {
        printf 'FAIL proc stat: expected <%s>, got <%s>\n' "$1" "$actual" >&2
        exit 1
    }
}
prefix='4242 (zclassic23) S 1 4242 4242 0 -1 4194560 900 0 3 0'
middle='0 0 20 0 12 0 55 9999'
doc="$prefix 731 219 $middle 262144 0"
check '950 262144' "$doc"
check '950 262144' "4242 () x (y z) ${doc#*) }"
check '0 0' "$prefix 0 0 $middle 0"
check '950 0007' "$prefix 731 219 $middle 0007"
check '950 9007199254740993' "$prefix 731 219 $middle 9007199254740993"
check '-1 -1' ''
check '-1 -1' '4242 no closing parenthesis'
check '-1 -1' '4242 (x) S 1 2'
check '950 -1' "$prefix 731 219"
for bad in invalid -1 +1 1.0 1e3; do
    check '-1 262144' "$prefix $bad 219 $middle 262144"
    check '-1 262144' "$prefix 731 $bad $middle 262144"
    check '950 -1' "$prefix 731 219 $middle $bad"
done
check '950 262144' "${doc// /$'\t'}"
check '950 262144' "$doc"$'\n'
printf 'proc stat counter values: PASS\n'

# Exact integer arithmetic and independent missing counters. Bash must not
# interpret leading zeroes as octal or wrap overflowing CPU totals.
check '17 262144' "$prefix 0008 0009 $middle 262144"
check '0 262144' "$prefix 000000000000000000000 0 $middle 262144"
check '9007199254740994 262144' "$prefix 9007199254740993 1 $middle 262144"
check '9223372036854775807 262144' "$prefix 9223372036854775806 1 $middle 262144"
for bad in 9223372036854775808 18446744073709551616; do
    check '-1 262144' "$prefix $bad 0 $middle 262144"
    check '-1 262144' "$prefix 0 $bad $middle 262144"
done
check '-1 262144' "$prefix 9223372036854775807 1 $middle 262144"
check '950 -1' "$prefix 731 219 $middle invalid"
printf 'proc stat integer boundaries: PASS\n'

# Drive the real caller too: no live process, node, datadir or RPC is used.
cat() {
    case "$1" in
        /proc/123/stat) printf '%s\n' "$doc" ;;
        /proc/123/io) printf 'read_bytes: 4096\nwrite_bytes: 8192\n' ;;
        *) return 1 ;;
    esac
}
PID=123 CLK_TCK=100 PAGE_KB=4
refresh_process_counters
[[ $LAST_CPU_SECONDS == 9.50 && $LAST_RSS_KB == 1048576 &&
   $LAST_DISK_READ_BYTES == 4096 && $LAST_DISK_WRITE_BYTES == 8192 ]]
doc="$prefix invalid 219 $middle 262144"
refresh_process_counters
[[ $LAST_CPU_SECONDS == -1 && $LAST_RSS_KB == 1048576 ]]
doc="$prefix 731 219"
refresh_process_counters
[[ $LAST_CPU_SECONDS == 9.50 && $LAST_RSS_KB == -1 ]]
doc="$prefix 731 219 $middle 262144 0"
PID=999
if ! refresh_process_counters; then
    echo 'FAIL: missing process should leave unavailable counters' >&2
    exit 1
fi
[[ $LAST_CPU_SECONDS == -1 && $LAST_RSS_KB == -1 &&
   $LAST_DISK_READ_BYTES == -1 && $LAST_DISK_WRITE_BYTES == -1 ]]
PID=''
refresh_process_counters
[[ $LAST_CPU_SECONDS == -1 && $LAST_RSS_KB == -1 &&
   $LAST_DISK_READ_BYTES == -1 && $LAST_DISK_WRITE_BYTES == -1 ]]
printf 'proc stat caller conversion and missing counters: PASS\n'
PID=123
awk() {
    printf 'awk\n' >> "$fixture/calls"
    command awk "$@"
}
: > "$fixture/calls"
refresh_process_counters
calls=$(wc -l < "$fixture/calls")
unset -f awk
printf 'resource sample: external_parsers=%s\n' "$calls"
if (( bench )); then
    TIMEFORMAT='500 resource samples: %3R s wall, %3U s user, %3S s system'
    time for ((i=0;i<500;i++)); do refresh_process_counters; done
fi
[[ $calls == 0 ]] || { echo 'FAIL: resource sample launched an external parser' >&2; exit 1; }
printf 'proc stat process budget: PASS\n'
