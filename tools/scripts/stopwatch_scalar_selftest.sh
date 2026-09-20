#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Hermetic artifact-reader regression and optional process-cost benchmark.
# Usage: bash tools/scripts/stopwatch_scalar_selftest.sh [--baseline] [--bench] [checker]
set -euo pipefail
export LC_ALL=C
baseline=0 bench=0
while [[ ${1:-} == --* ]]; do
    case $1 in
        --baseline) baseline=1 ;;
        --bench) bench=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
subject=${1:-$root/tools/scripts/stopwatch_artifact_symmetry_check.sh}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-stopwatch-scalar.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
sed -n '/^pj_scalar() {/,/^}/p' "$subject" > "$fixture/reader.sh"
. "$fixture/reader.sh"
declare -F pj_scalar >/dev/null

# Preserve the original fixed-emitter scalar policy, including numeric
# prefixes and undecoded string escapes. This is not a general JSON parser.
reference() {
    grep -oE "\"$2\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|-?[0-9]+|true|false|null)" "$1" 2>/dev/null |
        head -1 | sed -E "s/^\"$2\"[[:space:]]*:[[:space:]]*//; s/^\"//; s/\"$//"
}
checks=0
for doc in '' '{}' '{"verdict":"pass"}' '{"verdict": ""}' \
    '{"verdict":false}' '{"verdict":true}' '{"verdict":null}' \
    '{"verdict":-123}' '{"verdict":9007199254740993}' \
    '{"verdict":1.5}' '{"verdict":"back\\slash"}' \
    '{"verdict":[],"verdict":"seam"}' \
    '{"verdict":"pass","verdict":"seam"}' \
    '{"verdict_extra":"wrong","verdict":"seam"}' \
    $'{\n  "verdict"\t: "pass"\n}' \
    $'{"verdict":"pass"}\n{"verdict":"seam"}' \
    '{"verdict":"é→"}' '{"nested":{"verdict":"seam"}}'; do
    printf '%s' "$doc" > "$fixture/proof.json"
    expected_rc=0 actual_rc=0
    reference "$fixture/proof.json" verdict > "$fixture/expected" || expected_rc=$?
    pj_scalar "$fixture/proof.json" verdict > "$fixture/actual" || actual_rc=$?
    cmp "$fixture/expected" "$fixture/actual"
    [[ $actual_rc == "$expected_rc" ]]
    checks=$((checks + 1))
done
rc=0
pj_scalar "$fixture/absent.json" verdict > "$fixture/actual" || rc=$?
[[ $rc != 0 && ! -s $fixture/actual ]]

# A long artifact with repeated keys used to turn a successful first value
# into SIGPIPE through grep | head. Extra evidence cannot invalidate the
# already-observed field, nor require processing all remaining records.
awk 'BEGIN { for (i=0; i<100000; i++) print "{\"verdict\":\"pass\"}" }' > "$fixture/proof.json"
rc=0
pj_scalar "$fixture/proof.json" verdict > "$fixture/actual" || rc=$?
printf 'pass\n' > "$fixture/expected"
cmp "$fixture/expected" "$fixture/actual"
printf 'large artifact: first value=pass status=%s\n' "$rc"
if (( !baseline )); then [[ $rc == 0 ]]; fi

: > "$fixture/tools"
(
    grep() { echo grep >> "$fixture/tools"; command grep "$@"; }
    head() { echo head >> "$fixture/tools"; command head "$@"; }
    sed() { echo sed >> "$fixture/tools"; command sed "$@"; }
    awk() { echo awk >> "$fixture/tools"; command awk "$@"; }
    pj_scalar "$fixture/proof.json" verdict > /dev/null || :
)
count=$(wc -l < "$fixture/tools")
printf 'scalar reader: differential cases=%s external tools=%s\n' "$checks" "$count"
if (( !baseline )); then [[ $count == 1 ]]; fi

if (( !baseline )); then
    (
        # Observe records visited by the shipped awk program. Stdio read-ahead
        # is permitted; processing later evidence after a match is unnecessary.
        awk() {
            [[ $1 == -v && $2 == key=verdict ]]
            command awk -v visits="$fixture/visits" "$1" "$2" '
                { print NR > visits }
            '"$3" "${@:4}"
        }
        pj_scalar "$fixture/proof.json" verdict > /dev/null
    )
    [[ $(cat "$fixture/visits") == 1 ]]
fi

if (( bench )); then
    for shape in small large; do
        if [[ $shape == small ]]; then
            printf '{"verdict":"pass"}\n' > "$fixture/bench.json"
        else
            cp "$fixture/proof.json" "$fixture/bench.json"
        fi
        for trial in 1 2 3; do
            TIMEFORMAT="$shape trial=$trial reads=200 wall=%3R user=%3U sys=%3S seconds"
            time for ((i=0; i<200; i++)); do
                pj_scalar "$fixture/bench.json" verdict > /dev/null || :
            done
        done
    done
fi
if (( baseline )); then
    echo 'BASELINE: scalar output compatibility measured; cost/status gates not enforced'
else
    echo 'PASS: scalar compatibility, missing file, large artifact and process budget'
fi
