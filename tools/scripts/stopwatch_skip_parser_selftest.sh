#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic stopwatch-ledger parsing regression and optional observer benchmark.
# Usage: bash tools/scripts/stopwatch_skip_parser_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
if (( $# > 1 )); then
    printf 'usage: %s [--bench] [library]\n' "$0" >&2
    exit 2
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export ZCL_STOPWATCH_SKIP_CLASSES_DEF="$script_dir/../../engine/services/include/services/stopwatch_skip_classes.def"
. "${1:-$script_dir/stopwatch_skip_class.sh}"
fixture=$(mktemp -d /tmp/zcl-skip-parser-selftest.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

check_field() {
    local label=$1 expected=$2 document=$3 key=${4:-verdict} actual
    actual=$(stopwatch_skip_row_field "$document" "$key") || true
    if [[ $actual != "$expected" ]]; then
        printf 'FAIL %s: expected [%s], got [%s]\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}
check_has() {
    local label=$1 expected=$2 document=$3 key=${4:-skip_reason} rc=0
    stopwatch_skip_row_has "$document" "$key" || rc=$?
    if [[ $rc != "$expected" ]]; then
        printf 'FAIL %s: expected status %s, got %s\n' "$label" "$expected" "$rc" >&2
        exit 1
    fi
}

check_field string skip '{"verdict":"skip"}'
check_field first-duplicate fail '{"verdict":"fail","verdict":"pass"}'
check_field missing '' '{}'
check_field empty '' '{"verdict":""}'
check_field null '' '{"verdict":null}'
check_field numeric '' '{"verdict":42}'
check_field similar-key '' '{"old_verdict":"pass","verdict_extra":"pass"}'
check_field compact-contract '' '{"verdict" : "pass"}'
check_field later-string pass '{"verdict":null,"verdict":"pass"}'
check_field multiline fail $'{\n"verdict":"fail"\n}\n{"verdict":"pass"}'
check_field split-value '' $'{"verdict":"fa\nil"}'
check_field empty-before-later '' $'{"verdict":""}\n{"verdict":"pass"}'
check_field literal-backslash 'a\b' '{"artifact_dir":"a\b"}' artifact_dir
# This legacy flat reader does not decode escapes; preserve its quote boundary.
check_field escaped-quote 'a\' '{"skip_reason":"a\"b"}' skip_reason
check_has empty 0 '{"skip_reason":""}'
check_has null 0 '{"skip_reason":null}'
check_has missing 1 '{}'
check_has similar-key 1 '{"old_skip_reason":"","skip_reason_extra":""}'
check_has compact-contract 1 '{"skip_reason" :""}'
check_has multiline 0 $'{\n"skip_reason":null\n}'
printf 'stopwatch-skip-parser: field semantics PASS (20 cases)\n'

# A failure followed by 1,000 benign skips still needs every verdict inspected:
# a later pass would reset the alarm. No classification is needed on this path.
printf '{"verdict":"fail"}\n' >"$fixture/history.jsonl"
for ((i=0; i<1000; i++)); do
    printf '{"verdict":"skip","artifact_dir":"/fixture","skip_reason":"no valid --client-rpc / ZCL_ND_CLIENT_RPCPORT given"}\n' \
        >>"$fixture/history.jsonl"
done
if (( bench )); then
    TIMEFORMAT='stopwatch-skip-parser: 1001 rows: wall=%3R user=%3U sys=%3S seconds'
    for ((trial=1; trial<=3; trial++)); do
        time result=$(stopwatch_no_pass_all_benign "$fixture/history.jsonl")
        [[ $result == 0 ]] || { echo 'FAIL: benchmark lost non-benign streak' >&2; exit 1; }
    done
fi

# Deterministic observer-cost gate; elapsed time is never an acceptance bar.
(
    PATH=/nonexistent
    check_field no-external-field fail '{"verdict":"fail"}'
    check_field no-external-missing '' '{}'
    check_has no-external-present 0 '{"skip_reason":""}'
    check_has no-external-absent 1 '{}'
    result=$(stopwatch_no_pass_all_benign "$fixture/history.jsonl")
    [[ $result == 0 ]] || { echo 'FAIL: scan without parser tools lost non-benign streak' >&2; exit 1; }
)
printf 'stopwatch-skip-parser: no external parser tools PASS\n'
