#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Profile counter retries: exact selection and copy cost, without a node/RPC.
# Usage: sh tools/scripts/fold_profile_retry_cost_selftest.sh [--baseline] [--bench] [source]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-fold-retries.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
awk '
    /^jnums1\(\)/ { copying=1; starts++ }
    copying { print }
    copying && /^}/ { copying=0; ends++ }
    END { if (starts != 1 || ends != 1) exit 1 }
' "$subject" > "$fixture/reader.sh"
. "$fixture/reader.sh"

# Retry past null and disallowed field prefixes. Preserve the first integer,
# wide text, repeated requested keys and the existing comma/quote boundaries.
for size in 0 1 240 248 255 256 257 265 512 4096; do
    padding=$(awk -v n="$size" 'BEGIN { printf "%" n "s", "" }')
    [ "$(jnums1 "{\"blocks\":null,${padding}\"blocks\":-0007,\"blocks\":88}" blocks)" = \
        '-0007' ] || fail "split retry key $size"
    response="{\"blocks\":null,${padding}\"other\":{\"blocks\":99},\"blocks\":-0007,\"blocks\":88,\"total_us\":9007199254740993}
{\"blocks\":77}"
    [ "$(jnums1 "$response" 'blocks missing blocks total_us')" = \
        '-0007,0,-0007,9007199254740993' ] || fail "retry boundary $size"
done
key=$(awk 'BEGIN { for (i=0; i<300; i++) printf "k" }')
padding=$(awk 'BEGIN { printf "%255s", "" }')
[ "$(jnums1 "{\"$key\":null,${padding}\"$key\":18446744073709551615}" "$key")" = \
    '18446744073709551615' ] || fail 'wide key overlap'

# Observe the real reader's substring requests, not a second implementation.
# Timing uses the uninstrumented function. A work bound stays deterministic
# when host load makes elapsed-time assertions unreliable.
sed 's/substr(\$0, offset/counted_tail($0, offset/g
    /        BEGIN {/i\
        function counted_tail(text, offset, size, result) {\
            result = size == "" ? substr(text, offset) : substr(text, offset, size)\
            copied += length(result); probes++; return result\
        }
    /        END {/a\
            print probes + 0, copied + 0 > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"
for count in 1000 10000; do
    awk -v n="$count" 'BEGIN {
        printf "{"
        for (i=0; i<n; i++) printf "\"blocks\":null,"
        print "\"blocks\":9007199254740993,\"blocks\":8}"
    }' > "$fixture/response"
    response=$(cat "$fixture/response")
    (
        . "$fixture/counted.sh"
        jnums1 "$response" blocks
    ) > "$fixture/result" 2> "$fixture/cost"
    [ "$(cat "$fixture/result")" = '9007199254740993' ] || fail 'first usable value'
    read -r probes copied < "$fixture/cost"
    [ "$probes" -gt 0 ] || fail 'missing copy instrumentation'
    printf 'unavailable=%s search_substrings=%s copied_bytes=%s\n' "$count" "$probes" "$copied"
    if [ "$bench" = 1 ]; then
        printf 'benchmark: 20 uninstrumented reads, unavailable=%s\n' "$count"
        time sh -ec '
            . "$1"
            response=$(cat "$2")
            i=0
            while [ "$i" -lt 20 ]; do
                [ "$(jnums1 "$response" blocks)" = 9007199254740993 ] || exit 1
                i=$((i + 1))
            done
        ' sh "$fixture/reader.sh" "$fixture/response"
    fi
    if [ "$baseline" = 0 ]; then
        [ "$copied" -le "$((count * 300))" ] || fail 'quadratic retry copying'
    fi
done
# No valid value must still produce the missing sentinel, even over many retries.
response=$(awk 'BEGIN {
    for (i=0; i<1000; i++) printf "\"blocks\":null,"
    print "\"blocks\":false}"
}')
[ "$(jnums1 "$response" blocks)" = 0 ] || fail 'all unavailable sentinel'
if [ "$baseline" = 1 ]; then
    echo 'PASS: retry selection; baseline copy cost reported without a bound'
else
    echo 'PASS: retry selection, overlap and copy budget'
fi
