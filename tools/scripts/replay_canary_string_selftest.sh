#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Replay-canary string observation compatibility and process-cost regression.
# Usage: bash tools/scripts/replay_canary_string_selftest.sh [--bench] [harness]
set -euo pipefail
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
harness=${1:-$script_dir/replay_canary.sh}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/zcl-replay-string.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
# Extract only the reader; never source or start the live replay driver.
sed -n '/^json_str() {/,/^}/p' "$harness" > "$scratch/reader.sh"
. "$scratch/reader.sh"
declare -F json_str >/dev/null
checks=0 failures=0
check() {
    local label=$1 document=$2 key=$3 expected=$4 actual rc=0
    actual=$(json_str "$document" "$key") || rc=$?
    checks=$((checks + 1))
    if [ "$rc" != 0 ] || [ "$actual" != "$expected" ]; then
        printf 'FAIL %s: expected <%s> rc=0, got <%s> rc=%s\n' \
            "$label" "$expected" "$actual" "$rc" >&2
        failures=$((failures + 1))
    fi
}
check state '{"state":"complete"}' state complete
check hash '{"sha3_hash":"abcdef0123456789"}' sha3_hash abcdef0123456789
check amount '{"total_amount":"10364137.94674881"}' total_amount 10364137.94674881
check blanks $'{"state" \t\r\v\f: \t\r\v\f"complete"}' state complete
check pretty $'{\n  "state": "complete"\n}' state complete
check empty-value '{"state":""}' state ''
check empty-document '' state ''
check absent '{"other":"complete"}' state ''
check similar-key '{"state_next":"failed","state":"complete"}' state complete
check null '{"state":null}' state ''
check number '{"state":42}' state ''
check boolean '{"state":true}' state ''
check unclosed '{"state":"complete}' state ''
check duplicate '{"state":"complete","state":"failed"}' state complete
check multiline-duplicate $'{"state":"complete"}\n{"state":"failed"}' state complete
check later-string '{"state":null,"state":42,"state":"complete"}' state complete
check newline-before-colon $'{"state"\n:"complete"}' state ''
check newline-after-colon $'{"state":\n"complete"}' state ''
check newline-in-value $'{"state":"com\nplete"}' state ''
check later-after-split $'{"state":\n"failed","state":"complete"}' state complete
# Preserve the existing field extractor's escape behavior. This optimization
# does not introduce general JSON decoding.
check escape-text '{"state":"com\tplete"}' state 'com\tplete'
check escaped-quote '{"state":"com\"plete"}' state 'com\'
check colon '{"state":"a:b"}' state 'a:b'
check terminal-colon '{"state":"a: "}' state 'a: '
check value-whitespace $'{"state":"com\t\r\v\fplete"}' state $'com\t\r\v\fplete'
printf -v padding '%262144s' ''
check large "{\"state\":\"complete\",\"padding\":\"$padding\",\"state\":\"failed\"}" state complete
printf 'replay string: %s compatibility checks, %s failures\n' "$checks" "$failures"

if [ "$bench" = 1 ]; then
    document='{"state":"complete","bestblock":"abcdef0123456789","total_amount":"10364137.94674881"}'
    for trial in 1 2 3; do
        TIMEFORMAT="trial $trial: 900 reads, wall=%3R s user=%3U s sys=%3S s"
        time for ((i=0; i<300; i++)); do
            for key in state bestblock total_amount; do
                value=$(json_str "$document" "$key")
                [ -n "$value" ]
            done
        done
    done
fi
# A deterministic gate independent of host timing: no external parser may be
# necessary. Command-substitution subshells remain part of the measured cost.
if ! (PATH=/nonexistent; value=$(json_str '{"state":"complete"}' state); [ "$value" = complete ]); then
    echo 'FAIL: string reader requires an external executable' >&2
    failures=$((failures + 1))
fi
[ "$failures" = 0 ] || exit 1
echo 'replay-canary-string: PASS (compatible observations, zero external parsers)'
