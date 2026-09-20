#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic service-property reader regression and sync-observer benchmark.
# Usage: bash tools/scripts/evidence_systemd_field_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C

bench=0
case "${1:-}" in
    --bench) bench=1; shift ;;
    --selftest) shift ;;
esac
script_dir="$(cd "$(dirname "$0")" && pwd)"
library="${1:-$script_dir/lib/evidence_sources.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-service-fields.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
unset ZCL_EVIDENCE_SOURCES_SH_LOADED
# shellcheck source=tools/scripts/lib/evidence_sources.sh
. "$library"

check() {
    local label="$1" input="$2" key="$3" expected="$4"
    evidence_systemd_field "$input" "$key" > "$fixture/actual"
    printf '%s' "$expected" > "$fixture/expected"
    cmp "$fixture/expected" "$fixture/actual"
    printf '  ok: %s\n' "$label"
}

show=$'NRestarts=0\nActiveEnterTimestamp=Fri 2026-09-18 12:00:00 UTC\nActiveState=active\nMainPID=1234'
check restart-count "$show" NRestarts $'0\n'
check timestamp "$show" ActiveEnterTimestamp $'Fri 2026-09-18 12:00:00 UTC\n'
check state "$show" ActiveState $'active\n'
check final-unterminated-line "$show" MainPID $'1234\n'
check final-terminated-line "$show"$'\n' MainPID $'1234\n'
check empty-input '' MainPID ''
check missing-property "$show" InvocationID ''
check exact-key $'NotMainPID=1\nMainPIDExtra=2\n MainPID=3\nMainPID=4' MainPID $'4\n'
check first-duplicate $'MainPID=1\nMainPID=2' MainPID $'1\n'
check empty-first-duplicate $'MainPID=\nMainPID=2' MainPID $'\n'
check literal-value $'Other=ignored\nValue=  x\\y=\t\"*?[a]\"\r  \n' Value $'  x\\y=\t\"*?[a]\"\r  \n'
check blank-lines $'\n\nMainPID=7\n\n' MainPID $'7\n'
check wide-number 'MainPID=18446744073709551615' MainPID $'18446744073709551615\n'

# Preserve the previous reader byte-for-byte for all supported property names.
# Include every non-NUL value byte. Newline is a record boundary, tested above.
bytes=''
for ((i=1; i<=255; i++)); do
    [ "$i" -ne 10 ] || continue
    printf -v octal '%03o' "$i"
    printf -v byte '%b' "\\$octal"
    bytes+="$byte"
done
for input in "Value=$bytes" "$show"$'\nValue='"$bytes"$'\nValue=last'; do
    printf '%s\n' "$input" | sed -n 's/^Value=\(.*\)$/\1/p' |
        head -n1 > "$fixture/expected"
    evidence_systemd_field "$input" Value > "$fixture/actual"
    cmp "$fixture/expected" "$fixture/actual"
done
echo '  ok: differential value-byte coverage'

# Count external tools independently of timing and ordinary filesystem caches.
# These four reads are exactly the service fields used by node_slo_probe.sh.
: > "$fixture/tools"
(
    sed() { echo sed >> "$fixture/tools"; command sed "$@"; }
    head() { echo head >> "$fixture/tools"; command head "$@"; }
    for key in NRestarts ActiveEnterTimestamp ActiveState MainPID; do
        value="$(evidence_systemd_field "$show" "$key")"
        test -n "$value"
    done
)
tool_count="$(wc -l < "$fixture/tools")"
printf 'external text tools per four-property sample: %s (baseline: 8)\n' "$tool_count"

if [ "$bench" = 1 ]; then
    echo 'benchmark: 250 four-property samples (1000 reads), warm host caches'
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time (
        for ((i=0; i<250; i++)); do
            for key in NRestarts ActiveEnterTimestamp ActiveState MainPID; do
                value="$(evidence_systemd_field "$show" "$key")"
                test -n "$value"
            done
        done
    )
fi
if [ "$tool_count" -ne 0 ]; then
    echo 'selftest: FAIL service-property reads still start external text tools' >&2
    exit 1
fi
echo 'selftest: PASS service-property reader'
