#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the stopwatch's in-memory /proc/io reader without a node or datadir.
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
fixture=$(mktemp -d /tmp/z23-io-counter.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
sed -n '/^parse_proc_io_field() {/,/^}/p' "$subject" > "$fixture/reader.sh"
. "$fixture/reader.sh"
declare -F parse_proc_io_field >/dev/null || { echo 'missing I/O reader' >&2; exit 1; }
check() {
    local actual
    actual=$(parse_proc_io_field "$2" "${3:-read_bytes}")
    [[ $actual == "$1" ]] || {
        printf 'FAIL I/O counter: expected <%s>, got <%s>\n' "$1" "$actual" >&2
        exit 1
    }
}
doc=$'rchar: 9999999\nwchar: 8888888\nsyscr: 20\nsyscw: 10\nread_bytes: 4096000\nwrite_bytes: 8192000\ncancelled_write_bytes: 1234'
check 4096000 "$doc"
check 8192000 "$doc" write_bytes
check -1 "$doc" absent
check -1 ''
check -1 $'read_bytes:\nwrite_bytes: 123'
check -1 'read_bytes_extra: 123'
check -1 'cancelled_write_bytes: 123' write_bytes
check 0 'read_bytes: 0'
check 0007 'read_bytes: 0007'
check 18446744073709551615 'read_bytes: 18446744073709551615'
check 9007199254740993 'read_bytes: 9007199254740993'
check 12 $' \tread_bytes:\t 12 \t'
check 12 'read_bytes: 12 ignored trailing fields'
check 3 $'read_bytes: 3\nread_bytes: 4'
check 4 $'read_bytes: invalid\nread_bytes: 4'
for bad in -1 +1 1.0 1e3 0x10 '1junk' $'12\r'; do
    check -1 "read_bytes: $bad"
done
# Preserve the first match and the final line without a trailing newline.
printf -v padding '%2048s' ''
check 4096000 "$doc"$'\n'"padding: $padding"
check 4096000 "padding: $padding"$'\n'"$doc"
printf 'I/O counter values: PASS\n'

# Count actual external parser invocations; wall time alone is host-load noise.
awk() {
    printf 'awk\n' >> "$fixture/calls"
    command awk "$@"
}
: > "$fixture/calls"
check 4096000 "$doc"
check 8192000 "$doc" write_bytes
calls=$(wc -l < "$fixture/calls")
unset -f awk
printf 'two I/O counter reads: external_parsers=%s\n' "$calls"
if (( bench )); then
    TIMEFORMAT='500 poll pairs: %3R s wall, %3U s user, %3S s system'
    time for ((i=0;i<500;i++)); do
        # Match the command substitutions used by refresh_process_counters.
        read_value=$(parse_proc_io_field "$doc" read_bytes)
        write_value=$(parse_proc_io_field "$doc" write_bytes)
    done
    [[ $read_value == 4096000 && $write_value == 8192000 ]]
fi
[[ $calls == 0 ]] || { echo 'FAIL: I/O counters still launch an external parser' >&2; exit 1; }
printf 'I/O counter process budget: PASS\n'
