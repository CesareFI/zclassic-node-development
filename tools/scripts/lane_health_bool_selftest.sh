#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Purpose: qualify readiness-field parsing and observer cost without a node.
# Usage: bash tools/scripts/lane_health_bool_selftest.sh [--bench] [script]
set -euo pipefail
export LC_ALL=C

bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script="${1:-$(dirname "$0")/lane_health.sh}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zcl-lane-bool-selftest.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Extract only the real reader, so baseline comparison cannot contact a lane.
sed -n '/^json_first_bool_field() {/,/^}/p' "$script" > "$tmp/reader.sh"
. "$tmp/reader.sh"
declare -F json_first_bool_field >/dev/null

check() {
    local name="$1" expected="$2" body="$3" actual
    actual="$(json_first_bool_field "$body" ready)"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s: expected %s, got %s\n' "$name" "$expected" "$actual" >&2
        exit 1
    fi
}

check true 1 '{"ready":true}'
check false 0 '{"ready":false}'
check absent null '{}'
check empty null ''
check unknown null '{"ready":null}'
check string null '{"ready":"true"}'
check number null '{"ready":1}'
check case null '{"ready":TRUE}'
check exact_key null '{"not_ready":true}'
check first_true 1 '{"ready":true,"nested":{"ready":false}}'
check first_false 0 '{"ready":false,"nested":{"ready":true}}'
check first_boolean 0 '{"ready":null,"nested":{"ready":false}}'
check spaces 1 $'{"ready" \t: \rtrue}'
check first_line 0 $'{"ready":false}\n{"ready":true}'
check later_line 1 $'{}\n{"ready":true}'
check no_cross_line null $'{"ready":\ntrue}'
check no_final_newline 0 '{"ready":false}'
# Preserve the existing identifier-prefix behavior; this is not a JSON parser.
check prefix 1 '{"ready":true_suffix}'
printf -v padding '%*s' 262144 ''
check large_early 1 "{\"ready\":true}$padding"
check large_late 0 "$padding{\"ready\":false}"
echo 'lane-health boolean values: PASS (20 cases)'

if [ "$bench" = 1 ]; then
    sample='{"operator_needed":false,"readiness":{"chain_serving_ready":true,"agent_work_ready":false},"reducer":{"validation_pack_ok":false}}'
    TIMEFORMAT='1000 readiness readings: real=%R user=%U sys=%S'
    time for ((i=0; i<250; i++)); do
        for key in operator_needed chain_serving_ready agent_work_ready validation_pack_ok; do
            result="$(json_first_bool_field "$sample" "$key")"
        done
    done
fi

# Count actual external parser calls across command-substitution subshells.
# Wrappers still execute the real tools: values cannot pass via stub output.
grep() { printf 'grep\n' >> "$tmp/processes"; command grep "$@"; }
head() { printf 'head\n' >> "$tmp/processes"; command head "$@"; }
sed()  { printf 'sed\n'  >> "$tmp/processes"; command sed "$@"; }
awk()  { printf 'awk\n'  >> "$tmp/processes"; command awk "$@"; }
check budget 1 '{"ready":true}'
if [ -s "$tmp/processes" ]; then
    echo 'FAIL: readiness extraction started external parser tools' >&2
    cat "$tmp/processes" >&2
    exit 1
fi
echo 'lane-health boolean parser processes: 0 (PASS)'

# Also deny PATH lookup: wrappers above must not miss a parser called through
# `command`, or an external fallback used only for false or absent values.
PATH=/nonexistent check builtin_true 1 '{"ready":true}'
PATH=/nonexistent check builtin_false 0 '{"ready":false}'
PATH=/nonexistent check builtin_absent null '{}'
echo 'lane-health boolean reader without external tools: PASS'
