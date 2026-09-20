#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Bound repeated scanning of diagnostic prefixes in the IBD fold observer.
# Usage: sh tools/scripts/fold_profile_prefix_selftest.sh [--baseline] [--bench] [fold_profile.sh]
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
fixture=$(mktemp -d /tmp/zcl-drive-prefix.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^jnums()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || fail 'drive reader missing'
. "$fixture/reader.sh"
keys='blocks absent blocks'
stages='header_admit body_fetch header_admit'
expected='9007199254740993,0,9007199254740993,7,8,9,0,0,0,7,8,9'
for fields in 0 500 50000; do
    awk -v fields="$fields" 'BEGIN {
        printf "{"
        for (i = 1; i <= fields; i++) printf "\"diagnostic_%d\":%d,", i, i
        print "\"blocks_extra\":12,\"blocks\":null,\"header_admit\":9,\"body_fetch\":{\"us\":1,\"calls\":2,\"adv\":null}}"
        print "{\"blocks\":-0007,\"blocks\":9007199254740993,\"header_admit\":{\"us\":0004,\"calls\":5,\"adv\":6},\"header_admit\":{\"us\":7,\"calls\":8,\"adv\":9,\"skips\":0}}"
        print "{\"blocks\":99,\"header_admit\":{\"us\":99,\"calls\":99,\"adv\":99}}"
    }' > "$fixture/response"
    response=$(cat "$fixture/response")
    # Count bytes handed to the real regex operation, preserving its result
    # and RSTART/RLENGTH. Wall-time measurements below use the original reader.
    sed 's/match(rest, pattern\[i\])/counted_match(rest, pattern[i])/g
        /        BEGIN {/i\
        function counted_match(text, pattern) { probes++; bytes += length(text); return match(text, pattern) }
        /        END {/a\
            print probes + 0, bytes + 0 > "/dev/stderr"
    ' "$fixture/reader.sh" > "$fixture/counted.sh"
    (
        . "$fixture/counted.sh"
        jnums "$response" "$keys" "$stages"
    ) > "$fixture/result" 2> "$fixture/cost"
    [ "$(cat "$fixture/result")" = "$expected" ] || fail 'exact CSV or duplicate selection'
    read -r probes bytes < "$fixture/cost"
    [ "$probes" -gt 0 ] || fail 'regex measurement missing'
    printf 'diagnostic fields=%s regex calls=%s regex input bytes=%s\n' "$fields" "$probes" "$bytes"
    if [ "$bench" = 1 ]; then
        printf 'benchmark: 100 uninstrumented reads, diagnostic fields=%s\n' "$fields"
        time sh -ec '
            . "$1"
            response=$(cat "$2")
            i=0
            while [ "$i" -lt 100 ]; do
                [ "$(jnums "$response" "$3" "$4")" = "$5" ] || exit 1
                i=$((i + 1))
            done
        ' sh "$fixture/reader.sh" "$fixture/response" "$keys" "$stages" "$expected"
    fi
    if [ "$baseline" = 0 ]; then
        [ "$bytes" -le 4096 ] || fail 'diagnostic prefix rescanned by regex'
    fi
done
if [ "$baseline" = 1 ]; then
    echo 'PASS: exact observations; baseline work reported without a bound'
else
    echo 'PASS: exact observations and bounded regex prefix work'
fi
