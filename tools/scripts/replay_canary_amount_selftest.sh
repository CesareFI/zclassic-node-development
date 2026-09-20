#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exact-byte compatibility and process budget for replay supply observations.
# Usage: bash tools/scripts/replay_canary_amount_selftest.sh [--bench] [harness]
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
script_dir=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
harness=${1:-$script_dir/replay_canary.sh}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/zcl-replay-amount.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
# Never source the replay driver: only load these observation helpers.
sed -n '/^json_str() {/,/^}/p; /^json_amount() {/,/^}/p' "$harness" > "$scratch/readers.sh"
. "$scratch/readers.sh"
declare -F json_str json_amount >/dev/null
checks=0
check() {
    local label=$1 document=$2 expected=$3 rc=0
    json_amount "$document" total_amount > "$scratch/actual" || rc=$?
    printf '%s' "$expected" > "$scratch/expected"
    if [[ $rc != 0 ]] || ! cmp -s "$scratch/expected" "$scratch/actual"; then
        printf 'FAIL: %s (status=%s or byte mismatch)\n' "$label" "$rc" >&2
        exit 1
    fi
    checks=$((checks + 1))
}
check quoted '{"total_amount":"10364137.94674881"}' '10364137.94674881'
check unquoted '{"total_amount":10364137.94674881}' $'10364137.94674881\n'
check zero '{"total_amount":0}' $'0\n'
check fixed-zero '{"total_amount":0.00000000}' $'0.00000000\n'
check precision '{"total_amount":18446744073709551615.12345678}' $'18446744073709551615.12345678\n'
check missing '' ''
check absent '{"other":1}' ''
check empty-string '{"total_amount":""}' ''
check null '{"total_amount":null}' ''
check boolean '{"total_amount":true}' ''
check similar-key '{"total_amount_next":2,"total_amount":1}' $'1\n'
check whitespace $'{"total_amount" \t\r\v\f: \t\r\v\f1.25}' $'1.25\n'
check pretty $'{\n "total_amount": 1.25\n}' $'1.25\n'
check split-key $'{"total_amount"\n:1.25}' ''
check split-value $'{"total_amount":\n1.25}' ''
check later-after-split $'{"total_amount":\n2,"total_amount":1}' $'1\n'
check duplicate '{"total_amount":1,"total_amount":2}' $'1\n'
check duplicate-lines $'{"total_amount":1}\n{"total_amount":2}' $'1\n'
check quoted-precedence '{"total_amount":1,"total_amount":"2"}' '2'
check empty-quoted-fallback '{"total_amount":"","total_amount":2}' $'2\n'
check quoted-text '{"total_amount":"unavailable"}' 'unavailable'
# Preserve the existing extractor, including numeric-prefix behavior; this
# optimization does not redefine JSON validity or canary acceptance.
check negative '{"total_amount":-1.25}' ''
check plus '{"total_amount":+1.25}' ''
check exponent '{"total_amount":1.25e3}' $'1.25\n'
check leading-zero '{"total_amount":001.25}' $'001.25\n'
check dots '{"total_amount":1..25}' $'1..25\n'
check dot '{"total_amount":.}' $'.\n'
check unclosed-string '{"total_amount":"1.25}' ''
printf -v padding '%262144s' ''
check large "{\"total_amount\":1.25,\"padding\":\"$padding\",\"total_amount\":2}" $'1.25\n'
printf 'PASS: %s exact-byte/status cases\n' "$checks"

# Count actual parser calls, including those inside substitutions/pipelines.
: > "$scratch/calls"
(
    grep() { printf 'grep\n' >> "$scratch/calls"; command grep "$@"; }
    head() { printf 'head\n' >> "$scratch/calls"; command head "$@"; }
    sed() { printf 'sed\n' >> "$scratch/calls"; command sed "$@"; }
    json_amount '{"total_amount":10364137.94674881}' total_amount >/dev/null
)
calls=$(wc -l < "$scratch/calls")
printf 'external parser invocations per unquoted amount: %s\n' "$calls"
if (( bench )); then
    for trial in 1 2 3; do
        TIMEFORMAT="trial $trial: 300 captured reads, wall=%3R s user=%3U s sys=%3S s"
        time for ((i=0; i<300; i++)); do
            amount=$(json_amount '{"total_amount":10364137.94674881}' total_amount)
            [[ $amount == 10364137.94674881 ]]
        done
    done
fi
[[ $calls == 0 ]] || { echo 'FAIL: external amount parsers remain' >&2; exit 1; }
(
    PATH=/nonexistent
    amount=$(json_amount '{"total_amount":10364137.94674881}' total_amount)
    [[ $amount == 10364137.94674881 ]]
)
echo 'PASS: amount observer needs no external executable'
