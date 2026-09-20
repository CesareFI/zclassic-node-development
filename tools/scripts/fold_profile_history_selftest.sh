#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Summary endpoint regression and optional long-capture cost benchmark; no node.
# Usage: sh tools/scripts/fold_profile_history_selftest.sh [--bench] [fold_profile.sh]
set -eu
export LC_ALL=C
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
subject=${1:-$script_dir/fold_profile.sh}
fixture=$(mktemp -d /tmp/zcl-fold-history.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n '/^STAGES=/p; /^write_header() {/,/^}/p' "$subject" > "$fixture/header.sh"
. "$fixture/header.sh"
CSV=$fixture/header.csv
write_header
sed -n "/^awk -F, -v OFS=/,/^}' /{ /^awk -F, -v OFS=/d; s/^}' .*/}/; p; }" \
    "$subject" > "$fixture/summary.awk"
[ -s "$fixture/summary.awk" ] || { echo 'FAIL: summary program missing' >&2; exit 1; }

# 10,000 samples at the default 30-second cadence model a multi-day capture.
# Counters grow at different rates; middle rows must not alter endpoint deltas.
awk -F, 'NR == 1 {
    print
    for (row = 0; row < 10000; row++) {
        for (i = 1; i <= NF; i++) {
            delta = i * 11
            if ($i == "ts") delta = 30
            printf "%s%.0f", (i == 1 ? "" : ","), 2000000000000 + row * delta
        }
        printf "\n"
    }
}' "$CSV" > "$fixture/history.csv"
# Keep the very same endpoints, including an unterminated final record.
awk 'NR <= 2 {print} END {printf "%s", $0}' "$fixture/history.csv" > "$fixture/endpoints.csv"

check() {
    label=$1; shift
    "$@" -F, -v OFS=' ' -f "$fixture/summary.awk" "$fixture/history.csv" > "$fixture/full"
    "$@" -F, -v OFS=' ' -f "$fixture/summary.awk" "$fixture/endpoints.csv" > "$fixture/short"
    grep -q '^interval: 299970 s over 10000 samples$' "$fixture/full"
    grep -q '^interval: 299970 s over 2 samples$' "$fixture/short"
    sed 's/over 10000 samples/over 2 samples/' "$fixture/full" > "$fixture/normalized"
    cmp "$fixture/short" "$fixture/normalized"
    # Assert real endpoint arithmetic too, rather than only comparing two runs.
    awk '$1 == "header_admit" {
        if ($2 != 439956 || $4 != 549945 || $5 != 659934) exit 1
        found++
    } END {if (found != 1) exit 1}' "$fixture/full"
    echo "PASS: $label long history matches endpoint summary"
}
check awk awk
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN {exit 0}'; then
    check busybox-awk busybox awk
fi
if command -v mawk >/dev/null 2>&1; then check mawk mawk; fi

if [ "$bench" = 1 ]; then
    printf 'benchmark: 20 summaries of 10000 samples; CSV bytes: '
    wc -c < "$fixture/history.csv"
    time sh -ec '
        i=0
        while [ "$i" -lt 20 ]; do
            awk -F, -v OFS=" " -f "$1" "$2" > /dev/null
            i=$((i + 1))
        done
    ' sh "$fixture/summary.awk" "$fixture/history.csv"
fi
