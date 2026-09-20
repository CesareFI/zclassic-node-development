#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure scalar regex input in the real IBD drive observer; no node/network.
# Usage: sh tools/scripts/fold_profile_drive_window_selftest.sh [--baseline] [--bench] [source]
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
fixture=$(mktemp -d /tmp/zcl-drive-window.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^jnums()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || fail 'drive reader missing'
. "$fixture/reader.sh"
keys='drain_rounds_total batch_opened_total batch_committed_total batch_rolled_back_total batch_empty_total batch_commit_us_total fsync_flush_count fsync_flush_us_total'
expected='1,2,3,4,5,6,7,8'
sed 's/match(rest, pattern\[i\])/counted_match(rest, pattern[i])/g
    /        BEGIN {/i\
        function counted_match(text, pattern) { probes++; bytes += length(text); return match(text, pattern) }
    /        END {/a\
            print probes + 0, bytes + 0 > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"
for fields in 0 500 50000; do
    awk -v keys="$keys" -v fields="$fields" 'BEGIN {
        n = split(keys, key, " ")
        printf "{"
        for (i = 1; i <= n; i++) printf "\"%s\":%d,", key[i], i
        for (i = 1; i <= fields; i++) printf "\"diagnostic_%d\":%d,", i, i
        print "\"end\":0}"
    }' > "$fixture/response"
    response=$(cat "$fixture/response")
    (
        . "$fixture/counted.sh"
        jnums "$response" "$keys"
    ) > "$fixture/result" 2> "$fixture/cost"
    [ "$(cat "$fixture/result")" = "$expected" ] || fail 'exact drive counters'
    read -r probes bytes < "$fixture/cost"
    [ "$probes" -gt 0 ] || fail 'no regex work measured'
    printf 'diagnostic fields=%s regex calls=%s regex input bytes=%s\n' "$fields" "$probes" "$bytes"
    if [ "$bench" = 1 ]; then
        printf 'benchmark: 100 uninstrumented drive reads, diagnostic fields=%s\n' "$fields"
        time sh -ec '
            . "$1"
            response=$(cat "$2")
            i=0
            while [ "$i" -lt 100 ]; do
                [ "$(jnums "$response" "$3")" = "$4" ] || exit 1
                i=$((i + 1))
            done
        ' sh "$fixture/reader.sh" "$fixture/response" "$keys" "$expected"
    fi
    if [ "$baseline" = 0 ]; then
        [ "$bytes" -le 512 ] || fail 'scalar regex consumes diagnostic suffix'
    fi
done
# Exact text at window boundaries, with malformed and later valid duplicates.
for digits in 31 32 33 63 64 65 1000; do
    number=$(awk -v n="$digits" 'BEGIN {for (i=0; i<n; i++) printf "7"}')
    for suffix in '' '}' '.5,"blocks":null'; do
        [ "$(jnums "\"blocks\":null,\"blocks\":-$number$suffix" 'blocks blocks')" = "-$number,-$number" ] ||
            fail "wide scalar: $digits digits"
    done
done
[ "$(jnums '"blocks":1,"blocks":null,"blocks":-0007
"blocks":99' 'blocks absent')" = '-0007,0' ] || fail 'first line, last valid duplicate'
echo 'PASS: exact drive integers and measured scalar regex work'
