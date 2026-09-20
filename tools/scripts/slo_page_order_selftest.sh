#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Local sync-stall observer regression; no RPC, announcements or node state.
# Usage: bash tools/scripts/slo_page_order_selftest.sh [--bench [baseline.sh]]
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
PAGER="$SCRIPT_DIR/slo_page_if_stalled.sh"
REFERENCE="${2:-$PAGER}"
case "${1:-}" in
    ''|--bench) ;;
    *) echo "usage: $0 [--bench [baseline.sh]]" >&2; exit 2 ;;
esac
scratch="$(mktemp -d "${TMPDIR:-/tmp}/zcl-page-order.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

# Exercise the real evaluator, including all PAGE diagnostics and SUMMARY,
# without invoking the announcement layer. Existing --selftest covers that
# layer, exit codes and deduplication. Pin the shipped evaluation controls.
for source in candidate reference; do
    script="$PAGER"
    [ "$source" != reference ] || script="$REFERENCE"
    sed -n '/^evaluate_ledger() {/,/^}/p' "$script" >"$scratch/$source.sh"
done
cat >"$scratch/run.sh" <<'RUN'
set -euo pipefail
source "$1"
declare -F evaluate_ledger >/dev/null
LEDGER_FILE="$2"
STALE_SEC=300 UNREACH_SEC=600 ADVANCE_SEC=7200 ADV_MIN_TRAILING=2
COVERAGE_WINDOW_SEC=3600 COVERAGE_MIN_RATIO=0.5 COVERAGE_CADENCE_SEC=60
LIVE_INSTANCES=canonical
evaluate_ledger "$3"
RUN

fixture() {
    awk -v scenario="$1" -v n="$2" 'BEGIN {
        for (i = 0; i < n; i++) {
            t = 1700000000 + 60 * i
            h = 3000000 + i; oracle = h + i % 5; gap = i % 5; reach = "true"
            if (scenario == "flat" || scenario == "uptick") h = 3000000
            if (scenario == "uptick" && i == n-1) h++
            if (scenario == "outage" && i >= n-12) reach = "false"
            if (scenario == "regression" && i >= n-15) h -= 100
            if (scenario == "nulls" && i % 3 == 0) { h = "null"; oracle = "null"; gap = "null" }
            if (scenario == "coverage" && i % 10 != 0) continue
            printf "%d\t{\"ts\":%d,\"instance\":\"canonical\",\"reachable\":%s,\"served_height\":%s,\"oracle_height\":%s,\"gap_vs_oracle\":%s}\n", t, t, reach, h, oracle, gap
            if (scenario == "ties" && (i == 60 || i == n-1))
                printf "%d\t{\"ts\":%d,\"instance\":\"canonical\",\"reachable\":false,\"served_height\":null,\"oracle_height\":999,\"gap_vs_oracle\":-7}\n", t, t
        }
        # Other instances and unparsable rows must not enter canonical sorting.
        print "0\t{\"ts\":0,\"instance\":\"retired\",\"reachable\":false}"
        print "0\t{}"
    }'
}

reorder() {
    awk -v order="$1" '{ rows[NR] = $0 } END {
        if (order == "reverse") for (i = NR; i > 0; i--) print rows[i]
        else if (order == "interleaved") {
            for (i = 2; i <= NR; i += 2) print rows[i]
            for (i = 1; i <= NR; i += 2) print rows[i]
        } else if (order == "rotated") {
            for (i = int(NR/2)+1; i <= NR; i++) print rows[i]
            for (i = 1; i <= int(NR/2); i++) print rows[i]
        } else for (i = 1; i <= NR; i++) print rows[i]
    }' "$scratch/fixture.tsv"
}

compare() {
    local now="$1" expected actual
    cut -f2- "$scratch/ordered.tsv" >"$scratch/input.jsonl"
    sort -s -n -k1,1 "$scratch/ordered.tsv" | cut -f2- >"$scratch/sorted.jsonl"
    expected="$(bash "$scratch/run.sh" "$scratch/reference.sh" "$scratch/sorted.jsonl" "$now")"
    actual="$(bash "$scratch/run.sh" "$scratch/candidate.sh" "$scratch/input.jsonl" "$now")"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s/%s differs from stable numeric order\n%s\n%s\n' \
            "$scenario" "$order" "$expected" "$actual" >&2
        exit 1
    fi
    [[ "$actual" == *SUMMARY* ]] || { echo 'FAIL: missing evaluation' >&2; exit 1; }
}

for scenario in healthy flat uptick outage regression nulls coverage ties stale; do
    fixture "$scenario" 180 >"$scratch/fixture.tsv"
    now=1700010770
    # Force a PAGE for tied newest rows so its served/oracle/gap fields expose
    # any reordering; a healthy SUMMARY alone cannot observe those columns.
    case "$scenario" in stale|ties) now=$((now + 400)) ;; esac
    for order in ordered reverse interleaved rotated; do
        reorder "$order" >"$scratch/ordered.tsv"
        compare "$now"
    done
done
for count in 0 1 2 3 7 8 9 127 128 129; do
    scenario="size-$count" order=reverse
    fixture healthy "$count" >"$scratch/fixture.tsv"
    reorder "$order" >"$scratch/ordered.tsv"
    compare "$((1700000000 + count * 60))"
done
echo 'slo-page ordering: PASS (46 full evaluator comparisons, including timestamp ties)'

if [ "${1:-}" = --bench ]; then
    fixture healthy 4320 >"$scratch/fixture.tsv"
    sources=(candidate)
    [ -z "${2:-}" ] || sources=(reference candidate)
    for order in ordered reverse rotated; do
        reorder "$order" | cut -f2- >"$scratch/input.jsonl"
        for source in "${sources[@]}"; do
            TIMEFORMAT="$order 4320 canonical rows ($source): real=%R user=%U sys=%S"
            time actual="$(bash "$scratch/run.sh" "$scratch/$source.sh" "$scratch/input.jsonl" 1700259170)"
            [[ "$actual" == SUMMARY* && "$actual" == *canonical_samples=4320* ]] || {
                echo 'FAIL: benchmark fixture was not healthy' >&2; exit 1;
            }
        done
    done
fi
