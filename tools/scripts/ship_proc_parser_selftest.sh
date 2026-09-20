#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Pure startup-observer fixtures; no node, service, or datadir is accessed.
# --baseline FILE measures an older library without enforcing the process budget.
# --bench also times 300 samples (CPU, start and blocked-I/O fields per sample).
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
subject="$root/tools/scripts/ship_progress_lib.sh"
baseline=0
bench=0
while (( $# )); do
    case $1 in
        --baseline) subject=$2; baseline=1; shift ;;
        --bench) bench=1 ;;
        *) echo "ship-proc-parser: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done
. "$subject"
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-ship-proc-parser.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

# Number each field after comm, making any shift observable. The readers
# historically accept the first sufficiently long line and default to zero.
fields='S'
for (( i=2; i<=50; i++ )); do fields+=" $i"; done
record="7 (z23 (node) x) $fields"
cases=("" "garbage" "7 (short) S 2 3" "$record"
       $'\n'"$record" "$record"$'\n'"9 (later) $fields"
       "9 (no closing paren $fields" " 7 (leading space) $fields"
       "7 (x)) $fields" "7 () $fields")
for (( n=12; n<=40; n++ )); do
    cases+=("7 (truncated) $(awk -v n="$n" 'BEGIN {
        printf "S"; for (i=2; i<=n; i++) printf " %d", i
    }')")
done

# A deterministic cost rail: a sample needs one awk per field, no sed stage.
# Keep the reference reader outside this counter.
sed() { printf 'sed\n' >> "$fixture/sed.calls"; command sed "$@"; }
: > "$fixture/sed.calls"
for input in "${cases[@]}"; do
    for kind in cpu start blkio; do
        case $kind in
            cpu) column=13; expression='$12 + $13' ;;
            start) column=20; expression='$20' ;;
            blkio) column=40; expression='$40' ;;
        esac
        expected=$(printf '%s\n' "$input" |
            command sed 's/^[0-9][0-9]* (.*) //' |
            awk "NF >= $column && !seen { printf \"%.0f\\n\", $expression; seen=1 }
                 END { if (!seen) print 0 }")
        actual=$("ship_${kind}_ticks_from_text" "$input")
        if [[ $actual != "$expected" ]]; then
            printf 'FAIL %s: expected %s, got %s\n' "$kind" "$expected" "$actual" >&2
            exit 1
        fi
    done
done
unset -f sed
calls=$(wc -l < "$fixture/sed.calls")
printf 'ship-proc-parser: %s cases, sed invocations=%s\n' "${#cases[@]}" "$calls"
if (( !baseline && calls != 0 )); then
    echo 'FAIL: redundant sed processes remain in the startup observer' >&2
    exit 1
fi
if (( bench )); then
    TIMEFORMAT='ship-proc-parser: 300 samples real=%3R user=%3U sys=%3S seconds'
    time for (( i=0; i<300; i++ )); do
        ship_cpu_ticks_from_text "$record" > /dev/null
        ship_start_ticks_from_text "$record" > /dev/null
        ship_blkio_ticks_from_text "$record" > /dev/null
    done
fi
echo 'ship-proc-parser: PASS'
