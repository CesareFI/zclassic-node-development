#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic CSV regression and optional observer-cost benchmark. No node is run.
# Usage: sh tools/scripts/fold_profile_selftest.sh [--bench] [fold_profile.sh]
set -eu

bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
harness=${1:-$script_dir/fold_profile.sh}
fixture=$(mktemp -d /tmp/zcl-fold-profile-selftest.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Load only the actual sampling functions, before the copy/launch machinery.
sed -n '/^# .*sampling primitives/,/^# .*launch the copy/{ /^# .*launch the copy/d; p; }' \
    "$harness" > "$fixture/sampling.sh"
. "$fixture/sampling.sh"
CSV=$fixture/samples.csv

# Distinct sequential values make a dropped/reordered CSV column visible.
# The profile responses keep cumulative values before last_batch duplicates.
make_drive() {
    printf '{"drain_last_stage_us":{"header_admit":999},"drain_rounds_total":2,"drain_stage_totals":{'
    counter=3 separator=''
    for stage in $STAGES; do
        printf '%s"%s":{"us":%s,"calls":%s,"adv":%s%s}' \
            "$separator" "$stage" "$counter" "$((counter + 1))" "$((counter + 2))" "$1"
        separator=, counter=$((counter + 3))
    done
    printf '},"batch_opened_total":27,"batch_committed_total":28,"batch_rolled_back_total":29,"batch_empty_total":30,"batch_commit_us_total":31,"fsync_flush_count":32,"fsync_flush_us_total":33}'
}
ask() {
    case "$*" in
        'ops state --subsystem=reducer_stage_profile --key='*)
            if [ "${profile_fixture+x}" = x ]; then
                printf '%s' "$profile_fixture"
                return
            fi ;;
    esac
    case "$*" in
        'ops state --subsystem=reducer_drive') printf '%s' "$drive_fixture" ;;
        'ops state --subsystem=reducer_frontier') printf '%s' "$front_fixture" ;;
        'ops state --subsystem=reducer_stage_profile --key=proof_validate')
            printf '{"cumulative":{"stage":"proof_validate","blocks":34,"total_us":35,"pv_body_acquire_us":36,"pv_verify_us":37,"pv_log_insert_us":38,"pv_sapling_spends":39,"pv_sapling_outputs":40,"pv_sprout_groth16_joinsplits":41,"pv_sprout_phgr13_joinsplits":42,"pv_binding_sigs":43,"pv_lookahead_hits":44,"pv_lookahead_misses":45},"last_batch":{"blocks":900,"total_us":901}}' ;;
        'ops state --subsystem=reducer_stage_profile --key=tip_finalize')
            printf '{"cumulative":{"stage":"tip_finalize","blocks":46,"total_us":47},"last_batch":{"blocks":900,"total_us":901}}' ;;
        'ops state --subsystem=reducer_stage_profile --key=utxo_apply')
            printf '{"cumulative":{"stage":"utxo_apply","blocks":48,"total_us":49},"last_batch":{"blocks":900,"total_us":901}}' ;;
        *) echo "unexpected fixture RPC: $*" >&2; exit 1 ;;
    esac
}
date() { printf '1700000000\n'; }
front_fixture='{"provable_tip":1}'
expected=1700000000
counter=1
while [ "$counter" -le 49 ]; do
    expected=$expected,$counter
    counter=$((counter + 1))
done
failures=0
check_sample() {
    write_header
    sample_once
    actual=$(tail -n 1 "$CSV")
    if [ "$actual" = "$expected" ]; then
        printf 'PASS: %s\n' "$1"
    else
        printf 'FAIL: %s\n  expected %s\n  got      %s\n' "$1" "$expected" "$actual" >&2
        failures=$((failures + 1))
    fi
    awk -F, 'NF != 50 {exit 1} END {if (NR != 2) exit 1}' "$CSV" || {
        echo 'FAIL: CSV must have one header and one row of 50 columns' >&2
        failures=$((failures + 1))
    }
}

drive_fixture=$(make_drive '')
check_sample 'legacy stage schema, exact CSV and cumulative values'
drive_fixture=$(make_drive ',"skips":900')
check_sample 'current producer schema with skips, exact CSV'

# Count actual external parser invocations in one sample, regardless of wall
# time or host load. Function wrappers execute the real tools in each pipeline.
(
    sed() { printf 'sed\n' >> "$fixture/tools"; command sed "$@"; }
    head() { printf 'head\n' >> "$fixture/tools"; command head "$@"; }
    cut() { printf 'cut\n' >> "$fixture/tools"; command cut "$@"; }
    tr() { printf 'tr\n' >> "$fixture/tools"; command tr "$@"; }
    awk() { printf 'awk\n' >> "$fixture/tools"; command awk "$@"; }
    sample_once
)
tool_count=$(wc -l < "$fixture/tools" | tr -d ' ')
printf 'parser tools per sample: %s (before scalar batching: 22)\n' "$tool_count"
if [ "$tool_count" -gt 6 ]; then
    echo 'FAIL: repeated counter parsing exceeds 6 external tools per sample' >&2
    failures=$((failures + 1))
fi

# The existing absent-stage sentinel stays zero; wide counters stay text.
drive_fixture='{"drain_stage_totals":{"header_admit":{"us":18446744073709551615,"calls":0,"adv":7,"skips":1}},"drain_last_stage_us":{"header_admit":999}}'
write_header
sample_once
actual=$(tail -n 1 "$CSV" | cut -d, -f4-9)
if [ "$actual" != '18446744073709551615,0,7,0,0,0' ]; then
    echo "FAIL: wide counter, scalar shadow or missing-stage sentinel: $actual" >&2
    failures=$((failures + 1))
fi

# Preserve last object on the first matching line, including trailing skips.
# A later line, malformed object or scalar must not replace that observation.
drive_fixture='{"header_admit":{"us":1,"calls":2,"adv":3},"header_admit":{"us":0004,"calls":5,"adv":6,"skips":0},"header_admit":{"us":7,"calls":8,"adv":null}}
{"header_admit":{"us":9,"calls":10,"adv":11},"validate_headers":{"us":12,"calls":13,"adv":14}}
{"validate_headers":999}'
write_header
sample_once
actual=$(tail -n 1 "$CSV" | cut -d, -f4-12)
if [ "$actual" != '0004,5,6,12,13,14,0,0,0' ]; then
    echo "FAIL: stage duplicate, multiline or malformed-object handling: $actual" >&2
    failures=$((failures + 1))
else
    echo 'PASS: stage duplicates, multiline, malformed and scalar shadows'
fi

# Exercise the cumulative-profile columns through the real sampler, including
# the historical first-INTEGER match when a preceding value is null/string.
check_profile() {
    profile_fixture=$1
    write_header
    sample_once
    actual=$(tail -n 1 "$CSV" | cut -d, -f35-50)
    if [ "$actual" != "$2" ]; then
        printf 'FAIL: %s\n  expected %s\n  got      %s\n' "$3" "$2" "$actual" >&2
        failures=$((failures + 1))
    else
        printf 'PASS: %s\n' "$3"
    fi
    unset profile_fixture
}
# Missing fields in a successful nonempty response retain their sentinels.
# Entirely missing responses are rejected by fold_profile_rpc_selftest.sh.
check_profile '{}' '0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0' 'absent profile field sentinels'
check_profile '{"stage":"proof_validate","total_us":18446744073709551615,"blocks":-7,"pv_body_acquire_us":0,"pv_verify_us":-23,"pv_log_insert_us":0005,"pv_sapling_spends":9007199254740993,"pv_sapling_outputs":4,"pv_sprout_groth16_joinsplits":5,"pv_sprout_phgr13_joinsplits":6,"pv_binding_sigs":7,"pv_lookahead_hits":8,"pv_lookahead_misses":9,"last_batch":{"blocks":99,"total_us":100}}' \
    '-7,18446744073709551615,0,-23,0005,9007199254740993,4,5,6,7,8,9,-7,18446744073709551615,-7,18446744073709551615' \
    'reordered, negative, zero, wide and duplicate counters stay exact text'
check_profile '{"stage":"proof_validate","blocks":null,"total_us":"unknown",
"pv_body_acquire_us":null,"last_batch":{"stage":"proof_validate","blocks":18,"total_us":19,"pv_body_acquire_us":20},"blocks":21}' \
    '18,19,20,0,0,0,0,0,0,0,0,0,18,19,18,19' \
    'first integer match across lines and null/string values'

# Drive/frontier scalars historically choose the LAST integer on the FIRST
# matching line, unlike the stage-profile counters. Exercise through the CSV
# so batching must preserve both that policy and the noncontiguous columns.
front_fixture='{"provable_tip":0,"provable_tip":9007199254740993}
{"provable_tip":9}'
drive_fixture='{"drain_rounds_total":null,"batch_opened_total":1,"batch_opened_total":0002,"batch_opened_total":null,"batch_committed_total":-3,"fsync_flush_us_total":18446744073709551615,"batch_empty_total_extra":99}
{"drain_rounds_total":4,"drain_rounds_total":5,"batch_opened_total":9,"batch_rolled_back_total":"unknown","batch_commit_us_total":0,"fsync_flush_count":7}
{"drain_rounds_total":8,"batch_rolled_back_total":-6}'
write_header
sample_once
actual=$(tail -n 1 "$CSV" | cut -d, -f2-3,28-34)
if [ "$actual" != '9007199254740993,5,0002,-3,-6,0,0,7,18446744073709551615' ]; then
    echo "FAIL: scalar duplicates, missing keys or integer text: $actual" >&2
    failures=$((failures + 1))
else
    echo 'PASS: scalar duplicate policy, missing keys and exact wide integers'
fi
front_fixture='{"provable_tip":null}'
drive_fixture='{}'
write_header
sample_once
actual=$(tail -n 1 "$CSV" | cut -d, -f2-3,28-34)
if [ "$actual" != '0,0,0,0,0,0,0,0,0' ]; then
    echo "FAIL: absent scalar sentinels: $actual" >&2
    failures=$((failures + 1))
fi

if [ "$bench" = 1 ]; then
    drive_fixture=$(make_drive ',"skips":900')
    echo 'benchmark: 20 complete fixture samples (no RPC or sleep cost)'
    sed -n '/^make_drive()/,/^date()/p' "$0" > "$fixture/benchmark.sh"
    # POSIX time includes sample command substitutions and their real tools.
    time sh -ec '
        . "$1"
        . "$2"
        CSV=$3
        front_fixture=$5
        drive_fixture=$(make_drive "$4")
        n=0
        while [ "$n" -lt 20 ]; do sample_once; n=$((n + 1)); done
    ' sh "$fixture/sampling.sh" "$fixture/benchmark.sh" "$CSV" ',"skips":900' '{"provable_tip":1}'
fi
[ "$failures" = 0 ] || exit 1
echo 'fold-profile-selftest: PASS'
