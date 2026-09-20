#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Wide cumulative-count summary regression; synthetic CSV only, no node.
# Usage: sh tools/scripts/fold_profile_counts_selftest.sh [fold_profile.sh]
set -eu
export LC_ALL=C
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
subject=${1:-$script_dir/fold_profile.sh}
fixture=$(mktemp -d /tmp/zcl-fold-counts.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n '/^STAGES=/p; /^write_header() {/,/^}/p' "$subject" > "$fixture/header.sh"
. "$fixture/header.sh"
CSV=$fixture/header.csv
write_header
sed -n "/^awk -F, -v OFS=/,/^}' /{ /^awk -F, -v OFS=/d; s/^}' .*/}/; p; }" \
    "$subject" > "$fixture/summary.awk"
[ -s "$fixture/summary.awk" ] || { echo 'FAIL: missing summary program' >&2; exit 1; }

check() {
    label=$1; shift
    for count in 100 2147483647 2147483648 4294967296 1099511627776; do
        awk -F, -v count="$count" 'NR == 1 {
            print
            for (row = 0; row < 2; row++) {
                for (i = 1; i <= NF; i++) {
                    delta = count
                    if ($i == "ts") delta = 30
                    else if ($i ~ /_us($|_total$)/) delta = 2 * count
                    printf "%s%.0f", (i == 1 ? "" : ","), 10000 + row * delta
                }
                printf "\n"
            }
        }' "$fixture/header.csv" > "$fixture/counts.csv"
        "$@" -F, -v OFS=' ' -f "$fixture/summary.awk" "$fixture/counts.csv" > "$fixture/summary"
        awk -v expected="$count" '
            function equal(actual) {
                if (("x" actual) != ("x" expected)) {
                    print "FAIL: count expected " expected ": " $0 > "/dev/stderr"
                    failed = 1
                }
                checked++
            }
            /^header_admit |^validate_headers |^body_fetch |^body_persist |^script_validate |^proof_validate |^utxo_apply |^tip_finalize / {
                equal($4); equal($5)
                if ($6 != "2.0") failed = 1
            }
            /^TOTAL / { equal($4) }
            /^  batches / { equal($2 == "rolled" ? $4 : $3) }
            /^  durability barriers |^  blocks folded / { equal($3) }
            /^PROOF_VALIDATE / {
                actual = $2; sub(/^\(blocks=/, "", actual); sub(/\)$/, "", actual)
                equal(actual)
            }
            /^  sapling |^  sprout |^  binding sigs / { equal($3) }
            /^  lookahead hit\/miss / {
                split($3, pair, "/"); equal(pair[1]); equal(pair[2])
            }
            END { if (failed || checked != 31) exit 1 }
        ' "$fixture/summary" || {
            echo "FAIL: $label count=$count" >&2
            exit 1
        }
    done
    echo "PASS: $label exact stage, batch, barrier and proof counts through 2^40"
}
check awk awk
if command -v mawk >/dev/null 2>&1; then check mawk mawk; fi
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN {exit 0}'; then
    check busybox-awk busybox awk
else
    echo 'SKIP: BusyBox awk unavailable (integer-narrowing witness)'
fi
