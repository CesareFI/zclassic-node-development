#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Profile field-boundary cost and exact legacy selection; no node or RPC.
# Usage: sh tools/scripts/fold_profile_boundary_selftest.sh [--baseline] [--bench] [source.sh]
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
fixture=$(mktemp -d /tmp/zcl-profile-boundary.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^jnums1()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || fail 'profile reader missing'
. "$fixture/reader.sh"

# Exercise the nearest delimiter on both sides of each chunk boundary. A
# quote hides this occurrence; a comma admits it. The later integer and line
# must never replace an admitted first match. Preserve wide integer text.
for size in 0 1 126 127 128 129 254 255 256 257 4096; do
    padding=$(awk -v n="$size" 'BEGIN { printf "%" n "s", "" }')
    for prefix in '' ',' '"' '",'; do
        response="${prefix}${padding}\"blocks\":9007199254740993,\"blocks\":8
{\"blocks\":9}"
        expected=9007199254740993
        [ "$prefix" != '"' ] || expected=8
        actual=$(jnums1 "$response" 'blocks blocks absent')
        [ "$actual" = "$expected,$expected,0" ] || fail "boundary size=$size prefix=$prefix"
    done
done

# Instrument only the old per-character probes, leaving the production
# selection and scanner intact. The uninstrumented function is timed below.
sed '/c = substr(\$0, before, 1)/i\
                        probes++
    /        END {/a\
            print probes + 0 > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"
for size in 16 1048576; do
    awk -v n="$size" 'BEGIN {
        printf ",%" n "s\"blocks\":7,\"total_us\":9007199254740993}\n", ""
    }' > "$fixture/response"
    response=$(cat "$fixture/response")
    (
        . "$fixture/counted.sh"
        jnums1 "$response" 'blocks total_us'
    ) > "$fixture/result" 2> "$fixture/cost"
    [ "$(cat "$fixture/result")" = '7,9007199254740993' ] || fail 'instrumented result'
    read -r probes < "$fixture/cost"
    [ "$probes" -gt 0 ] || fail 'missing probe instrumentation'
    printf 'prefix bytes=%s character probes=%s\n' "$size" "$probes"
    if [ "$bench" = 1 ]; then
        printf 'benchmark: 20 uninstrumented reads, prefix bytes=%s\n' "$size"
        time sh -ec '
            . "$1"
            response=$(cat "$2")
            i=0
            while [ "$i" -lt 20 ]; do
                [ "$(jnums1 "$response" "blocks total_us")" = "7,9007199254740993" ] || exit 1
                i=$((i + 1))
            done
        ' sh "$fixture/reader.sh" "$fixture/response"
    fi
    if [ "$baseline" = 0 ]; then
        # One probe per skipped 128-byte span, at most one final span,
        # and the second key's adjacent delimiter.
        limit=$(( (size + 127) / 128 + 130 ))
        [ "$probes" -le "$limit" ] || fail 'field boundary still walks the entire prefix'
    fi
done
if [ "$baseline" = 1 ]; then
    echo 'PASS: exact values; baseline boundary work reported without a bound'
else
    echo 'PASS: exact nearest-delimiter selection, duplicate keys, missing keys and boundary work'
fi
