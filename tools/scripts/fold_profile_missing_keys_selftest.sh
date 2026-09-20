#!/bin/sh
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise missing-counter observer cost without a node, datadir or network.
# Usage: sh tools/scripts/fold_profile_missing_keys_selftest.sh [--baseline] [--bench] [fold_profile.sh]
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
fixture=$(mktemp -d /tmp/zcl-profile-missing-keys.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n '/^jnums1()/,/^}/p' "$subject" > "$fixture/reader.sh"
[ -s "$fixture/reader.sh" ] || { echo 'FAIL: reader missing' >&2; exit 1; }
. "$fixture/reader.sh"
keys='blocks total_us pv_body_acquire_us pv_verify_us pv_log_insert_us pv_sapling_spends pv_sapling_outputs pv_sprout_groth16_joinsplits pv_sprout_phgr13_joinsplits pv_binding_sigs pv_lookahead_hits pv_lookahead_misses'
expected='7,0,0,0,0,0,0,0,0,0,0,0'
# Instrument only regex calls; use the real match and preserve RSTART/RLENGTH.
# No timing assertion: the deterministic budget remains valid under host load.
sed 's/match(\$0, pattern\[i\])/counted_match($0, pattern[i])/g
    s/match(tail, pattern\[i\])/counted_match(tail, pattern[i])/g
    /        BEGIN {/i\
        function counted_match(text, pattern) { probes++; return match(text, pattern) }
    /        END {/a\
            print probes + 0 > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"
awk 'BEGIN {
    printf "{"
    for (i = 1; i <= 50000; i++) printf "\"diagnostic_%d\":%d,", i, i
    print "\"blocks\":7}"
}' > "$fixture/sparse.json"
response=$(cat "$fixture/sparse.json")
(
    . "$fixture/counted.sh"
    jnums1 "$response" "$keys"
) > "$fixture/result" 2> "$fixture/probes"
[ "$(cat "$fixture/result")" = "$expected" ] || { echo 'FAIL: sparse values' >&2; exit 1; }
probes=$(cat "$fixture/probes")
printf 'sparse profile: regex scans=%s (budget=1), bytes=' "$probes"
wc -c < "$fixture/sparse.json"
if [ "$baseline" = 0 ]; then
    [ "$probes" = 1 ] || { echo 'FAIL: absent counters trigger regex scans' >&2; exit 1; }
fi
# A literal key is only a prefilter: malformed/nested lookalikes cannot count
# as a value, and later valid fields must retain exact integer text.
actual=$(jnums1 '{"other":{"blocks":8},"blocks":null,"total_us":"unknown","blocks_extra":99}
{"blocks":-0007,"total_us":9007199254740993,"blocks":8}' 'blocks total_us')
[ "$actual" = '-0007,9007199254740993' ] || { echo 'FAIL: value policy' >&2; exit 1; }
# Complete profiles exercise the extra literal lookup on the success path.
awk -v keys="$keys" 'BEGIN {
    n = split(keys, key, " ")
    printf "{"
    for (i = 1; i <= n; i++) printf "%s\"%s\":%d", (i > 1 ? "," : ""), key[i], i
    for (i = 1; i <= 50000; i++) printf ",\"diagnostic_%d\":%d", i, i
    print "}"
}' > "$fixture/complete.json"
[ "$(jnums1 "$(cat "$fixture/complete.json")" "$keys")" = '1,2,3,4,5,6,7,8,9,10,11,12' ] || {
    echo 'FAIL: complete values' >&2; exit 1;
}
if [ "$bench" = 1 ]; then
    for shape in sparse complete; do
        if [ "$shape" = complete ]; then expected='1,2,3,4,5,6,7,8,9,10,11,12'; fi
        printf 'benchmark: shape=%s reads=30 (uninstrumented reader)\n' "$shape"
        time sh -ec '
            . "$1"
            response=$(cat "$2")
            i=0
            while [ "$i" -lt 30 ]; do
                [ "$(jnums1 "$response" "$3")" = "$4" ] || exit 1
                i=$((i + 1))
            done
        ' sh "$fixture/reader.sh" "$fixture/$shape.json" "$keys" "$expected"
    done
fi
echo 'PASS: missing-key work measured; sparse, complete and malformed values preserved'
