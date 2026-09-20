#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the real fold summary on synthetic cumulative counters, without a node.
# Usage: sh tools/scripts/fold_profile_summary_selftest.sh [fold_profile.sh]
set -eu
export LC_ALL=C
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
subject=${1:-$script_dir/fold_profile.sh}
fixture=$(mktemp -d /tmp/zcl-fold-summary.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Test the shipped summary and schema, without launching the copy harness.
sed -n '/^STAGES=/p; /^write_header() {/,/^}/p' "$subject" > "$fixture/header.sh"
. "$fixture/header.sh"
sed -n "/^awk -F, -v OFS=/,/^}' /{ /^awk -F, -v OFS=/d; s/^}' .*/}/; p; }" \
    "$subject" > "$fixture/summary.awk"
[ -s "$fixture/summary.awk" ] || { echo 'FAIL: summary program missing' >&2; exit 1; }
CSV=$fixture/samples.csv
write_header
cp "$CSV" "$fixture/header.csv"

check_summary() {
    label=$1
    shift
    # Signed-32-bit boundary, a two-hour stage, and counters below 2^53.
    for duration in 0 1073741823 1073741824 2147483647 2147483648 3600000000 1099511627776; do
        awk -F, -v duration="$duration" '
            NR == 1 {
                print
                for (row = 0; row < 3; row++) {
                    for (i = 1; i <= NF; i++) {
                        delta = 100
                        if ($i == "ts") delta = 7200
                        else if ($i == "header_admit_us") delta = duration
                        else if ($i ~ /_us$/) delta = 0
                        # A nonzero baseline makes accidental absolute totals fail.
                        printf "%s%.0f", (i == 1 ? "" : ","), 2000000000000 + row * delta
                    }
                    printf "\n"
                }
            }
        ' "$fixture/header.csv" > "$CSV"
        "$@" -F, -v OFS=' ' -f "$fixture/summary.awk" "$CSV" > "$fixture/summary"
        expected=$(awk -v duration="$duration" 'BEGIN { printf "%.0f", 2 * duration }')
        # Assert the actual difference and total, independently of table padding.
        awk -v expected="$expected" '
            $1 == "interval:" { if ($2 != 14400 || $5 != 3) exit 1; interval++ }
            $1 == "header_admit" {
                if ($2 != expected || $4 != 200 || $5 != 200) exit 1
                if ($3 != (expected > 0 ? 100 : 0)) exit 1
                stage++
            }
            $1 == "TOTAL" { if ($2 != expected || $4 != 200) exit 1; total++ }
            END { if (interval != 1 || stage != 1 || total != 1) exit 1 }
        ' "$fixture/summary" || {
            echo "FAIL: $label duration=$duration expected delta_us=$expected" >&2
            cat "$fixture/summary" >&2
            exit 1
        }
    done

    # An idle interval must not invent per-block or per-commit measurements.
    awk 'NR <= 2 {print} NR == 2 {print; exit}' "$CSV" > "$fixture/idle.csv"
    "$@" -F, -v OFS=' ' -f "$fixture/summary.awk" "$fixture/idle.csv" > "$fixture/summary"
    grep -q 'blocks folded         0  (no per-block figure: nothing folded)' "$fixture/summary"
    grep -q 'no proof_validate advance in the interval' "$fixture/summary"
    grep -q 'us per barrier        -' "$fixture/summary"
    grep -q 'us per commit         -' "$fixture/summary"

    # No measurement must stay explicitly unmeasured.
    for rows in 0 1; do
        head -n "$((rows + 1))" "$CSV" > "$fixture/short.csv"
        "$@" -F, -v OFS=' ' -f "$fixture/summary.awk" "$fixture/short.csv" > "$fixture/summary"
        printf '%s\n' 'fold_profile: fewer than 2 samples — nothing to difference' > "$fixture/expected"
        cmp "$fixture/expected" "$fixture/summary"
    done
    echo "PASS: $label summary differences, wide durations, zero and absent measurements"
}

check_summary awk awk
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN {exit 0}'; then
    check_summary busybox-awk busybox awk
else
    echo 'SKIP: BusyBox awk unavailable (32-bit integer-format witness)'
fi
if command -v mawk >/dev/null 2>&1; then check_summary mawk mawk; fi
