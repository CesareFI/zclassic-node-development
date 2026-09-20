#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Combined drive observation: exact CSV, parser budget and optional timings.
# Usage: sh tools/scripts/fold_profile_drive_selftest.sh [--bench] [fold_profile.sh]
set -eu
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
harness=${1:-$script_dir/fold_profile.sh}
fixture=$(mktemp -d /tmp/zcl-fold-drive.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n '/^# .*sampling primitives/,/^# .*launch the copy/{ /^# .*launch the copy/d; p; }' \
    "$harness" > "$fixture/sampling.sh"
. "$fixture/sampling.sh"
CSV=$fixture/samples.csv
fail() { printf 'fold-profile drive selftest: FAIL: %s\n' "$*" >&2; exit 1; }
date() { printf '1700000000\n'; }
ask() {
    case "$*" in
        'ops state --subsystem=reducer_drive') printf '%s\n' "$drive_fixture" ;;
        'ops state --subsystem=reducer_frontier') printf '{"provable_tip":17}\n' ;;
        'ops state --subsystem=reducer_stage_profile --key='*) printf '{}\n' ;;
        *) fail "unexpected RPC: $*" ;;
    esac
}

# Distinct scalar/stage duplicates, first matching lines, malformed objects,
# missing fields, wide integer text and leading zeros must survive batching.
drive_fixture='{"drain_rounds_total":1,"drain_rounds_total":0002,"header_admit":{"us":1,"calls":2,"adv":3},"header_admit":{"us":9007199254740993,"calls":0004,"adv":5,"skips":9},"header_admit":{"us":9,"calls":8,"adv":null},"batch_opened_total":null,"batch_empty_total":-6}
{"drain_rounds_total":99,"header_admit":{"us":99,"calls":99,"adv":99},"batch_opened_total":7,"batch_opened_total":0008,"batch_committed_total":9,"body_fetch":{"us":10,"calls":11,"adv":12},"fsync_flush_us_total":18446744073709551615}'
expected='1700000000,17,0002,9007199254740993,0004,5,0,0,0,10,11,12,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0008,9,0,-6,0,0,18446744073709551615,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0'
write_header
sample_once
[ "$(tail -n 1 "$CSV")" = "$expected" ] || fail 'combined scalar/stage CSV changed'
awk -F, 'NF != 50 {bad=1} END {exit (bad || NR != 2)}' "$CSV" || fail 'CSV shape'
[ "$(jstages "$drive_fixture" 'header_admit absent header_admit')" = \
    '9007199254740993,0004,5,0,0,0,9007199254740993,0004,5' ] || fail 'stage-only reader'
[ "$(jnums "$drive_fixture" 'drain_rounds_total absent drain_rounds_total')" = \
    '0002,0,0002' ] || fail 'scalar-only reader'

# Observe actual tool starts in the whole sampler, not a model of its reader.
(
    awk() { printf 'awk\n' >> "$fixture/tools"; command awk "$@"; }
    sed() { printf 'sed\n' >> "$fixture/tools"; command sed "$@"; }
    head() { printf 'head\n' >> "$fixture/tools"; command head "$@"; }
    tr() { printf 'tr\n' >> "$fixture/tools"; command tr "$@"; }
    cut() { printf 'cut\n' >> "$fixture/tools"; command cut "$@"; }
    sample_once
)
[ "$(tail -n 1 "$CSV")" = "$expected" ] || fail 'counted CSV changed'
count=$(wc -l < "$fixture/tools")
printf 'parser processes per complete sample: %s (baseline 6)\n' "$count"
printf 'fold-profile drive selftest: PASS (exact 50-column CSV)\n'

if [ "$bench" = 1 ]; then
    # Run uninstrumented complete observations with synthetic RPC responses.
    # No node, datadir, peer, network or sleep; host load is uncontrolled.
    printf 'benchmark: 200 complete fixture samples, warm tool/filesystem caches\n'
    cat "$fixture/sampling.sh" > "$fixture/benchmark.sh"
    sed -n '/^fail()/,/^write_header/{ /^write_header/d; p; }' "$0" >> "$fixture/benchmark.sh"
    time sh -ec '
        . "$1"
        CSV=$2
        i=0
        while [ "$i" -lt 200 ]; do
            sample_once
            i=$((i + 1))
        done
    ' sh "$fixture/benchmark.sh" "$CSV"
    [ "$(tail -n 1 "$CSV")" = "$expected" ] || fail 'benchmark CSV changed'
fi
[ "$count" -le 5 ] || fail "parser budget exceeded: $count > 5"
printf 'fold-profile drive selftest: PASS (parser budget)\n'
