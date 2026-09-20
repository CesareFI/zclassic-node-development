#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Sparse drive-observer cost and value regression; no node or network required.
# Usage: sh tools/scripts/fold_profile_drive_sparse_selftest.sh [--baseline] [--bench] [fold_profile.sh]
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
fixture=$(mktemp -d /tmp/zcl-drive-sparse.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^jnums()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || fail 'drive reader missing'
. "$fixture/reader.sh"
keys='drain_rounds_total batch_opened_total batch_committed_total batch_rolled_back_total batch_empty_total batch_commit_us_total fsync_flush_count fsync_flush_us_total'
stages='header_admit validate_headers body_fetch body_persist script_validate proof_validate utxo_apply tip_finalize'
expected='7,0,0,0,0,0,0,0,1,2,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0'
awk 'BEGIN {
    printf "{"
    for (i = 1; i <= 50000; i++) printf "\"diagnostic_%d\":%d,", i, i
    printf "\"drain_rounds_total\":7,\"header_admit\":{\"us\":1,\"calls\":2,\"adv\":3},"
    for (i = 1; i <= 50000; i++) printf "\"tail_%d\":%d,", i, i
    print "\"end\":0}"
}' > "$fixture/sparse.json"
response=$(cat "$fixture/sparse.json")
# Count the real regex operations without changing RSTART/RLENGTH or parsing.
# Each present column needs one regex match; absent duplicates need none.
sed 's/match(rest, pattern\[i\])/counted_match(rest, pattern[i])/g
    /        BEGIN {/i\
        function counted_match(text, pattern) { probes++; bytes += length(text); return match(text, pattern) }
    /        END {/a\
            print probes + 0, bytes + 0 > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"
(
    . "$fixture/counted.sh"
    jnums "$response" "$keys" "$stages"
) > "$fixture/result" 2> "$fixture/probes"
[ "$(cat "$fixture/result")" = "$expected" ] || fail 'sparse CSV values'
read -r probes bytes < "$fixture/probes"
printf 'sparse drive: regex scans=%s (budget=2), regex input bytes=%s, response bytes=' "$probes" "$bytes"
wc -c < "$fixture/sparse.json"

# Literal presence must not change matching, duplicate policy or exact integers.
actual=$(jnums '{"blocks_extra":12,"blocks":null,"header_admit":9,"body_fetch":{"us":1,"calls":2,"adv":null}}
{"blocks":-0007,"blocks":9007199254740993,"header_admit":{"us":0004,"calls":5,"adv":6},"header_admit":{"us":7,"calls":8,"adv":9,"skips":0}}
{"blocks":99,"header_admit":{"us":99,"calls":99,"adv":99}}' \
    'blocks absent blocks' 'header_admit body_fetch header_admit')
[ "$actual" = '9007199254740993,0,9007199254740993,7,8,9,0,0,0,7,8,9' ] || fail 'matching and duplicate policy'

if [ "$bench" = 1 ]; then
    printf 'benchmark: 30 sparse drive reads, uninstrumented reader\n'
    time sh -ec '
        . "$1"
        response=$(cat "$2")
        i=0
        while [ "$i" -lt 30 ]; do
            [ "$(jnums "$response" "$3" "$4")" = "$5" ] || exit 1
            i=$((i + 1))
        done
    ' sh "$fixture/reader.sh" "$fixture/sparse.json" "$keys" "$stages" "$expected"
fi
if [ "$baseline" = 0 ]; then
    [ "$probes" = 2 ] || fail 'absent drive fields or duplicates trigger regex scans'
fi
echo 'PASS: sparse drive values and observer-work measurement'
