#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Duplicate telemetry field selection and observer copying cost; no node/RPC.
# Usage: sh tools/scripts/fold_profile_duplicate_cost_selftest.sh [--baseline] [--bench] [source]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-fold-duplicates.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^jnums()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || fail 'drive reader missing'
. "$fixture/reader.sh"

# Put duplicate keys before, across and after the bounded search boundary.
# A malformed final occurrence must not replace the last valid observation.
for size in 0 1 240 248 255 256 257 265 512 4096; do
    padding=$(awk -v n="$size" 'BEGIN { printf "%" n "s", "" }')
    response="\"blocks\":1,\"stage\":{\"us\":1,\"calls\":2,\"adv\":3},${padding}\"blocks\":9007199254740993,\"stage\":{\"us\":0004,\"calls\":5,\"adv\":6},\"blocks\":null,\"stage\":null
\"blocks\":99,\"stage\":{\"us\":99,\"calls\":99,\"adv\":99}"
    [ "$(jnums "$response" 'blocks absent blocks' 'stage absent')" = \
        '9007199254740993,0,9007199254740993,0004,5,6,0,0,0' ] || fail "duplicate selection at padding $size"
done

# Even a key longer than the nearby window must be found across its edge.
key=$(awk 'BEGIN { for (i=0; i<300; i++) printf "k" }')
padding=$(awk 'BEGIN { printf "%255s", "" }')
[ "$(jnums "\"$key\":1,${padding}\"$key\":-0007" "$key")" = '-0007' ] || fail 'wide key overlap'

# Wrap the actual duplicate-search substring calls. Count bytes returned by
# substr, not an estimated cost or elapsed-time threshold on a loaded host.
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
        for (i=1; i<=n; i++) printf "\"blocks\":%d,", i
        print "\"blocks\":null}"
    }' > "$fixture/response"
    response=$(cat "$fixture/response")
    (
        . "$fixture/counted.sh"
        jnums "$response" blocks
    ) > "$fixture/result" 2> "$fixture/cost"
    [ "$(cat "$fixture/result")" = "$count" ] || fail 'last valid duplicate'
    read -r probes copied < "$fixture/cost"
    [ "$probes" -gt 0 ] || fail 'missing copy instrumentation'
    printf 'duplicates=%s search substrings=%s copied bytes=%s\n' "$count" "$probes" "$copied"
    if [ "$bench" = 1 ]; then
        printf 'benchmark: 20 uninstrumented reads, duplicates=%s\n' "$count"
        time sh -ec '
            . "$1"
            response=$(cat "$2")
            i=0
            while [ "$i" -lt 20 ]; do
                [ "$(jnums "$response" blocks)" = "$3" ] || exit 1
                i=$((i + 1))
            done
        ' sh "$fixture/reader.sh" "$fixture/response" "$count"
    fi
    if [ "$baseline" = 0 ]; then
        [ "$copied" -le "$(( (count + 1) * 300 ))" ] || fail 'duplicate search still copies quadratic suffix bytes'
    fi
done
if [ "$baseline" = 1 ]; then
    echo 'PASS: duplicate selection and boundary overlap; baseline copying reported without a bound'
else
    echo 'PASS: duplicate selection, boundary overlap and observer copy budget'
fi
