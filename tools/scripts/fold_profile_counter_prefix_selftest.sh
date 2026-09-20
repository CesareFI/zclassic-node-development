#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Bound stage-counter regex work after large IBD diagnostic prefixes.
# Usage: sh tools/scripts/fold_profile_counter_prefix_selftest.sh [--baseline] [--bench] [source]
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
fixture=$(mktemp -d /tmp/zcl-counter-prefix.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^jnums1()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || fail 'counter reader missing'
. "$fixture/reader.sh"
keys='blocks total_us blocks missing'
expected='-0007,9007199254740993,-0007,0'
# Count bytes entering the real regex, not elapsed time under variable load.
sed 's/match(\$0, pattern\[i\])/counted_match($0, pattern[i])/g
    s/match(tail, pattern\[i\])/counted_match(tail, pattern[i])/g
    /        BEGIN {/i\
        function counted_match(text, pattern) { probes++; bytes += length(text); return match(text, pattern) }
    /        END {/a\
            print probes + 0, bytes + 0 > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"
for fields in 0 500 50000; do
    awk -v fields="$fields" 'BEGIN {
        printf "{"
        for (i = 1; i <= fields; i++) printf "\"diagnostic_%d\":%d,", i, i
        print "\"blocks\":null,\"other\":{\"blocks\":8},\"blocks_extra\":99,\"blocks\":-0007,\"total_us\":9007199254740993,\"blocks\":23}"
        print "{\"blocks\":99,\"total_us\":99}"
    }' > "$fixture/response"
    response=$(cat "$fixture/response")
    (
        . "$fixture/counted.sh"
        jnums1 "$response" "$keys"
    ) > "$fixture/result" 2> "$fixture/cost"
    [ "$(cat "$fixture/result")" = "$expected" ] || fail 'exact counter CSV'
    read -r probes bytes < "$fixture/cost"
    [ "$probes" -gt 0 ] || fail 'instrumentation did not observe regex work'
    printf 'diagnostic fields=%s regex calls=%s regex bytes=%s\n' "$fields" "$probes" "$bytes"
    if [ "$bench" = 1 ]; then
        printf 'benchmark: 100 uninstrumented reads, diagnostic fields=%s\n' "$fields"
        time sh -ec '
            . "$1"
            response=$(cat "$2")
            i=0
            while [ "$i" -lt 100 ]; do
                [ "$(jnums1 "$response" "$3")" = "$4" ] || exit 1
                i=$((i + 1))
            done
        ' sh "$fixture/reader.sh" "$fixture/response" "$keys" "$expected"
    fi
    if [ "$baseline" = 0 ]; then
        [ "$bytes" -le 1024 ] || fail 'counter regex rescanned diagnostic prefix'
    fi
done
# Preserve the old comma/line boundary policy even for malformed input.
for prefix in '' '{' 'arbitrary text ' ',{' ',"other":{' '"other":{' '"'; do
    case "$prefix" in
        ',"other":{'|'"other":{'|'"') want=9 ;;
        *) want=-0007 ;;
    esac
    actual=$(jnums1 "${prefix}\"blocks\":-0007,\"blocks\":9" 'blocks')
    [ "$actual" = "$want" ] || fail "boundary: $prefix"
done
[ "$(jnums1 '"blocks":null"blocks":7,"blocks":8' 'blocks')" = 8 ] ||
    fail 'invalid occurrence lost quote boundary'
[ "$(jnums1 '"blocks":null
"blocks":-0007,"blocks":9' 'blocks')" = -0007 ] || fail 'multiline first value'
# Exercise window edges, growth, numeric prefixes and exact non-machine-width
# integer text. No conversion to awk floating-point numbers is allowed.
for digits in 31 32 33 63 64 65 1000; do
    number=$(awk -v n="$digits" 'BEGIN {for (i=0; i<n; i++) printf "7"}')
    for suffix in '' '}' '.5,"blocks":9'; do
        [ "$(jnums1 "\"blocks\":$number$suffix" 'blocks')" = "$number" ] ||
            fail "integer window: $digits digits"
        [ "$(jnums1 "\"blocks\":-$number$suffix" 'blocks')" = "-$number" ] ||
            fail "negative integer window: $digits digits"
    done
done
echo 'PASS: exact counters, malformed boundaries, duplicate selection and regex work'
