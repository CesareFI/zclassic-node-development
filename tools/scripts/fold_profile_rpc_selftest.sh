#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Required fold telemetry failures must not become zero-valued CSV samples.
# Usage: sh tools/scripts/fold_profile_rpc_selftest.sh [fold_profile.sh]
# Only extracted sampling functions and local fixtures run; no node is started.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
harness=${1:-$script_dir/fold_profile.sh}
fixture=$(mktemp -d /tmp/zcl-fold-profile-rpc.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n '/^# .*sampling primitives/,/^# .*launch the copy/{ /^# .*launch the copy/d; p; }' \
    "$harness" > "$fixture/sampling.sh"
. "$fixture/sampling.sh"
CSV=$fixture/samples.csv
fail() { printf 'fold-profile RPC selftest: FAIL: %s\n' "$*" >&2; exit 1; }

ask() {
    case "$*" in
        'ops state --subsystem=reducer_drive') endpoint=drive ;;
        'ops state --subsystem=reducer_frontier') endpoint=frontier ;;
        'ops state --subsystem=reducer_stage_profile --key=proof_validate') endpoint=proof_validate ;;
        'ops state --subsystem=reducer_stage_profile --key=tip_finalize') endpoint=tip_finalize ;;
        'ops state --subsystem=reducer_stage_profile --key=utxo_apply') endpoint=utxo_apply ;;
        *) fail "unexpected fixture RPC: $*" ;;
    esac
    printf '%s\n' "$endpoint" >> "$fixture/calls"
    if [ "$endpoint" = "$fault" ]; then
        case "$mode" in
            failed_output) printf '{"provable_tip":999,"blocks":999}\n'; return 7 ;;
            failed_empty) return 7 ;;
            success_empty) return 0 ;;
            success_spaces) printf '   '; return 0 ;;
            success_tabs) printf '\t\t'; return 0 ;;
            success_lines) printf '\n\r\n'; return 0 ;;
            success_whitespace) printf ' \t\r\n\v\f '; return 0 ;;
        esac
    fi
    printf ' \t{"provable_tip":123,"drain_rounds_total":4,"blocks":5,"total_us":6}\r\n'
}
date() { printf 'timestamp\n' >> "$fixture/observations"; printf '1700000000\n'; }

# Keep a real successful row as the previous observation. A rejected sample
# must preserve both the CSV bytes and that last usable observation.
fault=none mode=none
write_header
sample_once || fail 'healthy telemetry rejected'
awk -F, 'NF != 50 {exit 1} END {if (NR != 2) exit 1}' "$CSV" || fail 'healthy CSV shape'
cp "$CSV" "$fixture/healthy.csv"
expected_calls=0
for fault in drive frontier proof_validate tip_finalize utxo_apply; do
    expected_calls=$((expected_calls + 1))
    for mode in failed_output failed_empty success_empty success_spaces success_tabs success_lines success_whitespace; do
        : > "$fixture/calls"
        : > "$fixture/observations"
        if sample_once > "$fixture/out" 2> "$fixture/err"; then
            fail "$fault/$mode appended an unusable sample ($(wc -l < "$fixture/calls") RPCs)"
        fi
        cmp -s "$CSV" "$fixture/healthy.csv" || fail "$fault/$mode changed the CSV"
        [ "$(wc -l < "$fixture/calls")" -eq "$expected_calls" ] || fail "$fault/$mode continued polling"
        [ ! -s "$fixture/observations" ] || fail "$fault/$mode formatted an invalid observation"
        [ -s "$fixture/err" ] || fail "$fault/$mode lacks failure context"
        printf 'PASS: %s/%s stops after %s RPCs; previous CSV preserved\n' "$fault" "$mode" "$expected_calls"
    done
done

# A transient refusal must not poison the next sampling interval.
fault=none mode=none
: > "$fixture/calls"
sample_once || fail 'sampling did not recover'
[ "$(wc -l < "$fixture/calls")" -eq 5 ] || fail 'recovery skipped a required RPC'
awk -F, 'NF != 50 {exit 1} END {if (NR != 3) exit 1}' "$CSV" || fail 'recovery CSV shape'
printf 'fold-profile RPC selftest: PASS (35 refusals and recovery with padded telemetry)\n'
