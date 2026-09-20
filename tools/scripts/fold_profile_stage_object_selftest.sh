#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Bound stage regex work independently of trailing IBD diagnostics.
# Usage: sh tools/scripts/fold_profile_stage_object_selftest.sh [--baseline] [--bench] [source]
set -eu
baseline=0 bench=0
while :; do
    case "${1:-}" in
        --baseline) baseline=1 ;;
        --bench) bench=1 ;;
        --*) echo "unknown option: $1" >&2; exit 2 ;;
        *) break ;;
    esac
    shift
done
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
subject=${1:-$script_dir/fold_profile.sh}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-stage-object.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^jnums()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || fail 'drive reader missing'
. "$fixture/reader.sh"
stages='header_admit body_fetch proof_validate state_apply'
expected='1,2,3,2,3,4,3,4,5,4,5,6'
sed 's/match(rest, pattern\[i\])/counted_match(rest, pattern[i])/g
    /        BEGIN {/i\
        function counted_match(text, pattern) { probes++; bytes += length(text); return match(text, pattern) }
    /        END {/a\
            print probes + 0, bytes + 0 > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"

# Preserve last valid match on the first matching line, even after malformed
# objects, nested occurrences, extra fields, and incomplete objects.
check() {
    [ "$(jnums "$1" '' 'stage absent stage')" = "$2,0,0,0,$2" ] || fail "$3"
}
check '"stage":{"us":null},"stage":{"us":1,"calls":2,"adv":3}' '1,2,3' 'malformed before valid'
check '"stage":{"us":1,"calls":2,"adv":3},"stage":{"us":null}' '1,2,3' 'malformed after valid'
check '"stage":{"us":null,"nested":{"stage":{"us":7,"calls":8,"adv":9}}}' '7,8,9' 'nested valid'
check '"stage":{"us":1,"calls":2,"adv":3,"extra":0},"stage":{"us":4,"calls":5,"adv":6,' '4,5,6' 'comma terminated incomplete object'
check '"stage":{"us":9007199254740993,"calls":0004,"adv":5}
"stage":{"us":9,"calls":9,"adv":9}' '9007199254740993,0004,5' 'first line and exact integer text'
check '"stage":{"us":1,"calls":2,"adv":3.5}' '0,0,0' 'invalid number'
wide=$(awk 'BEGIN {for (i=0; i<1000; i++) printf "7"}')
check "\"stage\":{\"us\":$wide,\"calls\":$wide,\"adv\":$wide}" "$wide,$wide,$wide" 'wide stage integers'

for fields in 0 500 50000; do
    awk -v stages="$stages" -v fields="$fields" 'BEGIN {
        n = split(stages, stage, " ")
        printf "{"
        for (i = 1; i <= n; i++)
            printf "\"%s\":{\"us\":%d,\"calls\":%d,\"adv\":%d},", stage[i], i, i+1, i+2
        for (i = 1; i <= fields; i++) printf "\"diagnostic_%d\":%d,", i, i
        print "\"end\":0}"
    }' > "$fixture/response"
    response=$(cat "$fixture/response")
    (
        . "$fixture/counted.sh"
        jnums "$response" '' "$stages"
    ) > "$fixture/result" 2> "$fixture/cost"
    [ "$(cat "$fixture/result")" = "$expected" ] || fail 'exact stage counters'
    read -r probes bytes < "$fixture/cost"
    [ "$probes" -eq 4 ] || fail 'expected four stage regex calls'
    printf 'diagnostic fields=%s regex calls=%s regex input bytes=%s\n' "$fields" "$probes" "$bytes"
    if [ "$bench" = 1 ]; then
        printf 'benchmark: 100 uninstrumented stage reads, diagnostic fields=%s\n' "$fields"
        time sh -ec '
            . "$1"
            response=$(cat "$2")
            i=0
            while [ "$i" -lt 100 ]; do
                [ "$(jnums "$response" "" "$3")" = "$4" ] || exit 1
                i=$((i + 1))
            done
        ' sh "$fixture/reader.sh" "$fixture/response" "$stages" "$expected"
    fi
    if [ "$baseline" = 0 ]; then
        [ "$bytes" -le 256 ] || fail 'stage regex consumes diagnostic suffix'
    fi
done
echo 'PASS: exact stage counters and bounded object regex work'
