#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic scalar-reader parity and process budget; optional baseline source.
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${1:-$ROOT/tools/scripts/stopwatch_evidence_judge.sh}"
TMP="$(mktemp -d /tmp/zcl-judge-fields.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
awk '/^fld_num\(\)/ { copy=1 }
     copy { print }
     /^fld_str\(\)/ { last=1 }
     last && /^}/ { exit }' "$SOURCE" > "$TMP/readers.sh"
. "$TMP/readers.sh"
declare -F fld_num fld_str >/dev/null

# Count external tools even when the production reader runs in a subshell.
grep() { printf 'grep\n' >> "$TMP/processes"; command grep "$@"; }
head() { printf 'head\n' >> "$TMP/processes"; command head "$@"; }
sed() { printf 'sed\n' >> "$TMP/processes"; command sed "$@"; }
: > "$TMP/processes"
check() {
    local reader="$1" input="$2" key="$3" expected="$4" expected_rc="$5" actual rc=0
    actual="$($reader "$input" "$key")" || rc=$?
    if [[ "$actual" != "$expected" || "$rc" != "$expected_rc" ]]; then
        printf 'FAIL %s key=%s output=<%s> rc=%s expected=<%s> rc=%s\n' \
            "$reader" "$key" "$actual" "$rc" "$expected" "$expected_rc" >&2
        exit 1
    fi
}
check fld_num '{"ts":0}' ts 0 0
check fld_num '{"ts":-123}' ts -123 0
check fld_num '{"ts":00012}' ts 00012 0
check fld_num '{"ts":123456789012345678901234567890}' ts 123456789012345678901234567890 0
check fld_num '{"ts":null,"ts":42,"ts":99}' ts 42 0
check fld_num $'{"ts":12}\n{"ts":34}' ts 12 0
check fld_num '{"ts":12.5}' ts 12 0
check fld_num '{"ts": 12}' ts '' 1
check fld_num '{"other":12}' ts '' 1
check fld_num '' ts '' 1
check fld_str '{"verdict":"pass"}' verdict pass 0
check fld_str '{"verdict":""}' verdict '' 0
check fld_str '{"verdict":null,"verdict":"fail","verdict":"pass"}' verdict fail 0
check fld_str $'{"verdict":"skip"}\n{"verdict":"pass"}' verdict skip 0
check fld_str $'{"verdict":"bad\nvalue"}' verdict '' 1
check fld_str $'{"verdict":"bad\nvalue","verdict":"fail"}' verdict fail 0
check fld_str '{"artifact_dir":"/tmp/a b:c\\d"}' artifact_dir '/tmp/a b:c\\d' 0
check fld_str '{"verdict": "pass"}' verdict '' 1
check fld_str '{"verdict":"unterminated}' verdict '' 1
check fld_str '{}' verdict '' 1
echo 'PASS: exact scalar bytes and missing-field exit status (20 cases)'

: > "$TMP/processes"
TIMEFORMAT='500 paired scalar reads: %3R s wall, %3U s user, %3S s system'
time for ((i=0; i<500; i++)); do
    check fld_num '{"ts":2000000000,"verdict":"pass"}' ts 2000000000 0
    check fld_str '{"ts":2000000000,"verdict":"pass"}' verdict pass 0
done
count=0
while IFS= read -r tool; do count=$((count + 1)); done < "$TMP/processes"
printf 'scalar-reader external processes: %s\n' "$count"
if ((count != 0)); then
    echo 'FAIL: scalar readers must not launch external parsing tools' >&2
    exit 1
fi
echo 'PASS: scalar-reader process budget'
