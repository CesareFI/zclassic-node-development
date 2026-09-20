#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure profile boundary probes without a node, RPC or chain data.
# Usage: sh tools/scripts/fold_profile_boundary_jump_selftest.sh [--baseline] [--bench] [source]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-boundary-jump.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^jnums1()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || fail 'missing reader'
. "$fixture/reader.sh"

# The nearest delimiter wins even when both kinds occur inside one span.
# Check every offset through two spans, first integer selection and exact text.
for size in $(awk 'BEGIN { for (i=0; i<=257; i++) print i }'); do
    padding=$(awk -v n="$size" 'BEGIN { printf "%" n "s", "" }')
    for prefix in ',"' '",'; do
        expected=8
        response="${prefix}${padding}\"blocks\":9007199254740993,\"blocks\":8"
        case "$prefix" in *',') expected=9007199254740993 ;; esac
        [ "$(jnums1 "$response" blocks)" = "$expected" ] || fail "nearest delimiter at $size"
    done
done

# Count actual boundary-loop probes. Timing uses the uninstrumented reader.
sed '/c = substr(\$0, before, 1)/i\
                        probes++
    /        END {/a\
            print probes + 0 > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"
for count in 12 1000; do
    awk -v n="$count" 'BEGIN {
        printf "{"
        for (i=0; i<n; i++) printf "%96s\"blocks\":null,", ""
        printf "%96s\"blocks\":9007199254740993,\"blocks\":8}\n", ""
    }' > "$fixture/response"
    response=$(cat "$fixture/response")
    (
        . "$fixture/counted.sh"
        jnums1 "$response" blocks
    ) > "$fixture/result" 2> "$fixture/cost"
    [ "$(cat "$fixture/result")" = 9007199254740993 ] || fail 'first integer after unavailable counters'
    read -r probes < "$fixture/cost"
    [ "$probes" -gt 0 ] || fail 'missing instrumentation'
    printf 'unavailable=%s boundary probes=%s\n' "$count" "$probes"
    if [ "$bench" = 1 ]; then
        printf 'benchmark: 100 uninstrumented reads, unavailable=%s\n' "$count"
        time sh -ec '
            . "$1"
            response=$(cat "$2")
            i=0
            while [ "$i" -lt 100 ]; do
                [ "$(jnums1 "$response" blocks)" = 9007199254740993 ] || exit 1
                i=$((i + 1))
            done
        ' sh "$fixture/reader.sh" "$fixture/response"
    fi
    if [ "$baseline" = 0 ]; then
        [ "$probes" -le "$((2 * (count + 1)))" ] || fail 'boundary span still inspected byte by byte'
    fi
done
echo 'PASS: nearest delimiter, exact first integer and measured boundary work'
