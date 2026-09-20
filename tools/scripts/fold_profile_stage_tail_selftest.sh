#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Stage triples must not copy later fields inside the same diagnostic object.
# Usage: sh tools/scripts/fold_profile_stage_tail_selftest.sh [--baseline] [--bench] [source]
set -eu
export LC_ALL=C
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-stage-tail.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^jnums()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || fail 'drive reader missing'
. "$fixture/reader.sh"
sed 's/substr(\$0, start, window)/counted_window($0, start, window)/g
    /        BEGIN {/i\
        function counted_window(text, start, window, result) { result = substr(text, start, window); copies++; bytes += length(result); return result }
    /        END {/a\
            print copies + 0, bytes + 0 > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"

for fields in 0 500 50000; do
    awk -v fields="$fields" 'BEGIN {
        printf "{\"stage\":{\"us\":1,\"calls\":2,\"adv\":3,"
        for (i=1; i<=fields; i++) printf "\"diagnostic_%d\":%d,", i, i
        print "\"end\":0}}"
    }' > "$fixture/response"
    response=$(cat "$fixture/response")
    (
        . "$fixture/counted.sh"
        jnums "$response" '' stage
    ) > "$fixture/result" 2> "$fixture/cost"
    [ "$(cat "$fixture/result")" = '1,2,3' ] || fail 'stage triple changed'
    read -r copies bytes < "$fixture/cost"
    [ "$copies" -gt 0 ] || fail 'window copies not measured'
    printf 'extra stage fields=%s window copies=%s copied bytes=%s\n' "$fields" "$copies" "$bytes"
    if [ "$baseline" = 0 ]; then
        [ "$bytes" -le 128 ] || fail 'stage window consumes fields after the triple'
    fi
    if [ "$bench" = 1 ]; then
        printf 'benchmark: 100 uninstrumented reads, extra stage fields=%s\n' "$fields"
        time sh -ec '
            . "$1"
            response=$(cat "$2")
            i=0
            while [ "$i" -lt 100 ]; do
                [ "$(jnums "$response" "" stage)" = "1,2,3" ] || exit 1
                i=$((i + 1))
            done
        ' sh "$fixture/reader.sh" "$fixture/response"
    fi
done

# Stopping early still searches later occurrences, including inside the same
# object, and preserves the first matching line and exact wide integer text.
padding=$(awk 'BEGIN {for (i=0; i<1000; i++) printf "x"}')
for opening in '"stage":{"us":1,"calls":2,"adv":3,' '"stage":{"us":null,'; do
    response="$opening\"extra\":\"$padding\",\"stage\":{\"us\":7,\"calls\":8,\"adv\":9}}"
    [ "$(jnums "$response" '' 'stage absent stage')" = '7,8,9,0,0,0,7,8,9' ] ||
        fail 'later nested stage must win'
done
for digits in 31 64 127 128 129 511 1000; do
    number=$(awk -v n="$digits" 'BEGIN {for (i=0; i<n; i++) printf "7"}')
    response="\"stage\":{\"us\":$number,\"calls\":0002,\"adv\":3,\"extra\":\"$padding\"}"
    [ "$(jnums "$response" '' stage)" = "$number,0002,3" ] || fail 'wide stage integers'
done
[ "$(jnums '"stage":{"us":1,"calls":2,"adv":3,
"stage":{"us":7,"calls":8,"adv":9}' '' stage)" = '1,2,3' ] || fail 'first matching line'
[ "$(jnums '"stage":{"us":1,"calls":2,"adv":3.5}' '' stage)" = '0,0,0' ] || fail 'invalid triple'
echo 'PASS: exact stage triples without copying later object fields'
