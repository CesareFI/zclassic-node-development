#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure stage-window copies in the real observer; no node or network.
# Usage: sh tools/scripts/fold_profile_stage_window_selftest.sh [--baseline] [--bench] [source]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-stage-window.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^jnums()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || fail 'drive reader missing'
. "$fixture/reader.sh"
# Count the bytes actually returned by stage-window substr calls. Preserve
# awk match state and parser output; the counters go only to stderr.
sed 's/substr(\$0, start, window)/counted_window($0, start, window)/g
    /        BEGIN {/i\
        function counted_window(text, start, window, result) { result = substr(text, start, window); copies++; bytes += length(result); return result }
    /        END {/a\
            print copies + 0, bytes + 0 > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"
for fields in 0 500 50000; do
    response=$(awk -v fields="$fields" 'BEGIN {
        printf "{\"stage\":{\"us\":1,\"calls\":2,\"adv\":3},"
        for (i=1; i<=fields; i++) printf "\"diagnostic_%d\":%d,", i, i
        print "\"end\":0}"
    }')
    (
        . "$fixture/counted.sh"
        jnums "$response" '' stage
    ) > "$fixture/result" 2> "$fixture/cost"
    [ "$(cat "$fixture/result")" = '1,2,3' ] || fail 'stage values changed'
    read -r copies bytes < "$fixture/cost"
    [ "$copies" -gt 0 ] || fail 'window copies not measured'
    printf 'diagnostic fields=%s window copies=%s copied bytes=%s\n' "$fields" "$copies" "$bytes"
    if [ "$bench" = 1 ]; then
        printf '%s\n' "$response" > "$fixture/response"
        printf 'benchmark: 100 uninstrumented stage reads, diagnostic fields=%s\n' "$fields"
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
    if [ "$baseline" = 0 ]; then
        [ "$bytes" -le 128 ] || fail 'stage window copies diagnostic suffix'
    fi
done
# Growth must retain exact integer text and must not require a closing brace:
# the historical reader also accepts a triple terminated by a comma.
for digits in 31 64 127 128 129 511 1000; do
    number=$(awk -v n="$digits" 'BEGIN {for (i=0; i<n; i++) printf "7"}')
    for suffix in '}' ','; do
        response="\"stage\":{\"us\":$number,\"calls\":0002,\"adv\":3$suffix"
        [ "$(jnums "$response" '' stage)" = "$number,0002,3" ] || fail 'wide or incomplete stage'
    done
done
echo 'PASS: exact stage values and measured window copies'
