#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Tip decoder equivalence and observer process budget. No node or network.
# Usage: bash tools/scripts/c3_stopwatch_tip_decode_selftest.sh [--baseline] [source.sh]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
source_file=${1:-$root/tools/scripts/c3_stopwatch_triple_run.sh}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-tip-decode.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
awk '/^(json_field|tip_h_hash)\(\) \{/ {copy=1}
     copy {print} copy && /^}/ {copy=0}' "$source_file" > "$fixture/functions.sh"
# Load only the pure decoders, never the driver's live path.
. "$fixture/functions.sh"
check() {
    local label=$1 expected=$2 actual
    actual=$(tip_h_hash "$3")
    [[ $actual == "$expected" ]] || {
        printf 'FAIL: %s expected <%s>, got <%s>\n' "$label" "$expected" "$actual" >&2
        exit 1
    }
}
hash=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
doc='{"ok":true,"height":3200000,"hash":"'"$hash"'"}'
check compact "3200000 $hash" "$doc"
check genesis "0 $hash" '{"hash":"'"$hash"'","height":0,"ok":true}'
check multiline "42 $hash" $'{\n "ok" : true,\n "height" : 42,\n "hash" : "'"$hash"$'"\n}'
check quoted-height "42 $hash" '{"ok":true,"height":"42","hash":"'"$hash"'"}'
check wide-height "9007199254740993 $hash" '{"ok":true,"height":9007199254740993,"hash":"'"$hash"'"}'
check first-duplicate "7 $hash" '{"ok":true,"height":7,"height":8,"hash":"'"$hash"'"}'
check false '-1 -' '{"ok":false,"height":99,"hash":"abc"}'
check missing-ok '-1 -' '{"height":99,"hash":"abc"}'
check empty '-1 -' ''
check null '-1 -' null
check missing-height "-1 $hash" '{"ok":true,"hash":"'"$hash"'"}'
check negative "-1 $hash" '{"ok":true,"height":-2,"hash":"'"$hash"'"}'
check decimal "-1 $hash" '{"ok":true,"height":2.5,"hash":"'"$hash"'"}'
check missing-hash '42 -' '{"ok":true,"height":42}'
check empty-hash '42 -' '{"ok":true,"height":42,"hash":""}'

# Trace inherited DEBUG traps to observe actual child shell processes. The
# decoder itself runs in this shell with output redirected, not substituted.
: > "$fixture/processes"
set -T
trap 'if (( BASH_SUBSHELL > 0 )); then printf "%s\n" "$BASHPID" >> "$fixture/processes"; fi' DEBUG
tip_h_hash "$doc" > "$fixture/result"
trap - DEBUG
set +T
processes=$(sort -u "$fixture/processes" | wc -l)
printf 'tip_decode child_shells_per_sample=%s\n' "$processes"
if [[ $baseline == 0 ]]; then
    (( processes == 0 )) || { echo 'FAIL: tip decoder forks child shells' >&2; exit 1; }
    # Prove external parsing programs are unnecessary too.
    PATH=/nonexistent tip_h_hash "$doc" > "$fixture/result"
    [[ $(< "$fixture/result") == "3200000 $hash" ]] || {
        echo 'FAIL: decoding without external programs' >&2; exit 1;
    }
fi
# Timings are observations, never a flaky pass/fail threshold. Three warm
# trials; process count above is the deterministic performance regression.
TIMEFORMAT='tip_decode 200_samples real=%3R user=%3U sys=%3S'
for trial in 1 2 3; do
    time for ((i=0; i<200; i++)); do tip_h_hash "$doc" > /dev/null; done
done
echo 'c3-stopwatch-tip-decode: PASS (15 fixtures)'
