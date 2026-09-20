#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic ordering regression and optional observer-cost benchmark. No nodes.
# Usage: bash tools/scripts/slo_hold_order_selftest.sh [--bench [baseline.sh]]
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
JUDGE="$SCRIPT_DIR/slo_hold_judge.sh"
REFERENCE="${2:-$JUDGE}"
case "${1:-}" in
    ''|--bench) ;;
    *) echo "usage: $0 [--bench [baseline.sh]]" >&2; exit 2 ;;
esac
scratch="$(mktemp -d "${TMPDIR:-/tmp}/zcl-hold-order.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/input" "$scratch/sorted"

# Prefix each row with its numeric timestamp for an independent stable sort
# oracle. Include distinct values in all four columns moved by the judge.
fixture() {
    awk -v scenario="$1" -v n="$2" 'BEGIN {
        for (i = 0; i < n; i++) {
            t = 1700000000 + 60 * i
            h = 3000000 + i; gap = i % 4; reachable = "true"
            if (scenario == "gap" && i == 60) gap = 9
            if (scenario == "outage" && i >= 30 && i <= 50) {
                reachable = "false"; h = "null"; gap = "null"
            }
            if (scenario == "regression" && i == 60) h -= 2
            if (scenario == "nulls" && i % 7 == 0) { h = "null"; gap = "null" }
            printf "%d\t{\"ts\":%d,\"instance\":\"canonical\",\"reachable\":%s,\"served_height\":%s,\"gap_vs_oracle\":%s}\n", t, t, reachable, h, gap
            if (scenario == "ties" && i == 60)
                printf "%d\t{\"ts\":%d,\"instance\":\"canonical\",\"reachable\":true,\"served_height\":%d,\"gap_vs_oracle\":0}\n", t, t, h-1
        }
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

run_judge() {
    local judge="$1" dir="$2" hours="$3" now="$4" rc=0
    ZCL_SLO_LEDGER_DIR="$dir" ZCL_SLO_PAGES_FILE="$scratch/pages.jsonl" \
        ZCL_SLO_NOW="$now" bash "$judge" --instance canonical \
        --window-hours "$hours" --gap-budget 3 || rc=$?
    printf 'exit=%s\n' "$rc"
}

for scenario in healthy gap outage regression nulls ties page; do
    fixture "$scenario" 120 >"$scratch/fixture.tsv"
    : >"$scratch/pages.jsonl"
    if [ "$scenario" = page ]; then
        printf '{"ts":1700003600,"instance":"canonical"}\n' >"$scratch/pages.jsonl"
    fi
    for order in ordered reverse interleaved rotated; do
        reorder "$order" >"$scratch/ordered.tsv"
        cut -f2- "$scratch/ordered.tsv" >"$scratch/input/uptime-ledger.jsonl"
        sort -s -n -k1,1 "$scratch/ordered.tsv" | cut -f2- >"$scratch/sorted/uptime-ledger.jsonl"
        expected="$(run_judge "$REFERENCE" "$scratch/sorted" 2 1700007170)"
        actual="$(run_judge "$JUDGE" "$scratch/input" 2 1700007170)"
        if [ "$actual" != "$expected" ]; then
            printf 'FAIL: %s/%s differs from stable numeric order\n%s\n%s\n' \
                "$scenario" "$order" "$expected" "$actual" >&2
            exit 1
        fi
        # Pin the observable consequence of preserving order within a tie.
        if [ "$scenario/$order" = ties/ordered ]; then
            [[ "$actual" == *'kind=regressed'* ]] || { echo 'FAIL: tie regression lost' >&2; exit 1; }
        elif [ "$scenario/$order" = ties/reverse ]; then
            [[ "$actual" == *'VERDICT=HOLD_PROVEN'* ]] || { echo 'FAIL: reversed tie order lost' >&2; exit 1; }
        fi
    done
done

# Ragged merge runs and the no-merge case. Large cases below are benchmark
# reports only; elapsed time never decides whether a correctness check passes.
for count in 1 2 3 7 8 9 127 128 129; do
    fixture healthy "$count" >"$scratch/fixture.tsv"
    reorder reverse | cut -f2- >"$scratch/input/uptime-ledger.jsonl"
    cut -f2- "$scratch/fixture.tsv" >"$scratch/sorted/uptime-ledger.jsonl"
    : >"$scratch/pages.jsonl"
    now=$((1700000000 + (count - 1) * 60 + 30))
    [ "$(run_judge "$JUDGE" "$scratch/input" 2 "$now")" = \
      "$(run_judge "$REFERENCE" "$scratch/sorted" 2 "$now")" ] || {
        echo "FAIL: $count rows differ from chronological order" >&2; exit 1;
    }
done
echo 'slo-hold ordering: PASS (37 full-output/exit comparisons, including timestamp ties)'

if [ "${1:-}" = --bench ]; then
    judges=("$JUDGE")
    [ -z "${2:-}" ] || judges=("$2" "$JUDGE")
    fixture healthy 4320 >"$scratch/fixture.tsv"
    for order in ordered reverse rotated; do
        reorder "$order" | cut -f2- >"$scratch/input/uptime-ledger.jsonl"
        for judge in "${judges[@]}"; do
            TIMEFORMAT="$order 4320 rows ($judge): real=%R user=%U sys=%S"
            time actual="$(run_judge "$judge" "$scratch/input" 72 1700259170)"
            [[ "$actual" == *'VERDICT=HOLD_PROVEN'* && "$actual" == *'exit=0' ]] || {
                echo 'FAIL: benchmark fixture did not prove hold' >&2; exit 1;
            }
        done
    done
fi
