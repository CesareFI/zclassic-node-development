#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Profile-reader regression and optional cost benchmark; no node is launched.
# Usage: sh tools/scripts/fold_profile_scan_selftest.sh [--bench] [fold_profile.sh]
set -eu
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
harness=${1:-$script_dir/fold_profile.sh}
fixture=$(mktemp -d /tmp/zcl-fold-profile-scan.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n '/^jnums1()/,/^}/p' "$harness" > "$fixture/reader.sh"
. "$fixture/reader.sh"
fail() { printf 'fold-profile scan selftest: FAIL: %s\n' "$*" >&2; exit 1; }
check() {
    actual=$(jnums1 "$1" "$2")
    [ "$actual" = "$3" ] || fail "$4: expected $3; got $actual"
}

check '{"blocks":7,"total_us":9007199254740993,"last_batch":{"blocks":8,"total_us":9}}' \
    'blocks total_us' '7,9007199254740993' 'cumulative precedes last_batch'
check '{"blocks":null,"total_us":-5}
{"blocks":0007,"total_us":9}' 'blocks total_us' '0007,-5' 'incomplete first line'
check '{"blocks":0,"blocks":99}
{"total_us":18446744073709551615}' 'blocks total_us' \
    '0,18446744073709551615' 'duplicate does not complete missing counter'
check '{"blocks":0,"blocks":99}' 'blocks total_us' '0,0' 'missing counter sentinel'
check '{"blocks":12,"total_us":34}' 'blocks blocks total_us' '12,12,34' 'repeated requested key'
check '{}' 'blocks total_us' '0,0' 'empty profile'
check '{"other":{"blocks":8},"blocks":9,"total_us":10}' \
    'blocks total_us' '9,10' 'first quote must name the requested field'
check '{"other":null,,  {"blocks":0009,"total_us":-10.5}' \
    'blocks total_us' '0009,-10' 'empty fields and legacy integer-prefix semantics'
check '{"blocks":null,"blocks":7,"total_us":8}' \
    'blocks total_us' '7,8' 'first integer match after null'
check '{"blocks":1,"blocks":2}' '' '' 'no requested columns'

# Model a response with cumulative counters followed by an unneeded diagnostic
# tail and last_batch. Keep it bounded and deterministic, with no RPC cost.
awk 'BEGIN {
    printf "{\"cumulative\":{\"stage\":\"tip_finalize\",\"blocks\":7,\"total_us\":9007199254740993}"
    for (i = 1; i <= 500; i++) printf ",\"diagnostic_%d\":%d", i, i
    print ",\"last_batch\":{\"blocks\":8,\"total_us\":9}}"
}' > "$fixture/response"
response=$(cat "$fixture/response")
check "$response" 'blocks total_us' '7,9007199254740993' 'long diagnostic tail'

# Count column probes in an instrumented copy of the actual reader.
# This adds only an observation, not a different reader or an early exit.
# Timing below uses the uninstrumented reader. Read the following line too:
# input still drains normally, without an early awk exit/SIGPIPE upstream.
sed '/if (!(i in value)/i\
                print "column" > "/dev/stderr"
    /if (i in value) continue/i\
                print "column" > "/dev/stderr"
' "$fixture/reader.sh" > "$fixture/counted.sh"
(
    . "$fixture/counted.sh"
    jnums1 "$response
$response" 'blocks total_us'
) > "$fixture/counted.out" 2> "$fixture/fields"
[ "$(cat "$fixture/counted.out")" = '7,9007199254740993' ] || fail 'instrumented output'
fields=$(wc -l < "$fixture/fields")
printf 'column probes for two profile lines: %s (baseline 6)\n' "$fields"

printf 'fold-profile scan selftest: PASS (11 value fixtures)\n'

if [ "$bench" = 1 ]; then
    printf 'benchmark: 500 profile reads; fixture bytes: '
    wc -c < "$fixture/response"
    time sh -ec '
        . "$1"
        response=$(cat "$2")
        i=0
        while [ "$i" -lt 500 ]; do
            result=$(jnums1 "$response" "blocks total_us")
            [ "$result" = "7,9007199254740993" ] || exit 1
            i=$((i + 1))
        done
    ' sh "$fixture/reader.sh" "$fixture/response"

    # Stress the allocation cost of splitting a large, unused diagnostic tail.
    # This is synthetic observer cost, not node or end-to-end IBD throughput.
    awk 'BEGIN {
        printf "{\"blocks\":7,\"total_us\":9007199254740993"
        for (i = 1; i <= 50000; i++) printf ",\"diagnostic_%d\":%d", i, i
        print "}"
    }' > "$fixture/large-response"
    printf 'benchmark: 100 large profile reads; fixture bytes: '
    wc -c < "$fixture/large-response"
    time sh -ec '
        . "$1"
        response=$(cat "$2")
        i=0
        while [ "$i" -lt 100 ]; do
            result=$(jnums1 "$response" "blocks total_us")
            [ "$result" = "7,9007199254740993" ] || exit 1
            i=$((i + 1))
        done
    ' sh "$fixture/reader.sh" "$fixture/large-response"
fi
[ "$fields" -eq 2 ] || fail "expected 2 column probes, got $fields"
printf 'fold-profile scan selftest: PASS (bounded column scan)\n'

# Drain a large multiline profile under pipefail: returning early must not
# give the printf producer SIGPIPE after the requested counters are found.
bash -o pipefail -ec '
    . "$1"
    response=$(cat "$2")
    for repeat in 1 2 3 4 5 6; do response="$response
$response"; done
    jnums1 "$response" "blocks total_us"
' bash "$fixture/reader.sh" "$fixture/response" > "$fixture/profile-drained.out"
[ "$(cat "$fixture/profile-drained.out")" = '7,9007199254740993' ] || fail 'drained profile output'

# The drive reader has a different duplicate policy: last match on the first
# matching line, for scalars and stage triples. It too must stop visiting
# output columns once complete, while still draining every input line.
sed -n '/^jnums()/,/^}/p' "$harness" > "$fixture/drive.sh"
. "$fixture/drive.sh"
check_drive() {
    actual=$(jnums "$1" "$2" "$3")
    [ "$actual" = "$4" ] || fail "drive values: expected $4; got $actual"
}
check_drive '{"blocks":1,"blocks":0007,"header_admit":{"us":1,"calls":2,"adv":3},"header_admit":{"us":9007199254740993,"calls":0,"adv":4,"skips":8}}
{"blocks":99,"header_admit":{"us":99,"calls":99,"adv":99}}' \
    'blocks blocks' 'header_admit header_admit' \
    '0007,0007,9007199254740993,0,4,9007199254740993,0,4'
check_drive '{"blocks":0,"blocks":99}
{"header_admit":{"us":12,"calls":13,"adv":14}}
{"total_us":18446744073709551615}' \
    'blocks total_us' 'header_admit' '99,18446744073709551615,12,13,14'
check_drive '{"blocks":null,"header_admit":{"us":1,"calls":2,"adv":null}}
{"blocks":-7}' 'blocks absent' 'header_admit' '-7,0,0,0,0'
check_drive '{"blocks":1}' '' '' ''

awk 'BEGIN {
    print "{\"blocks\":7,\"total_us\":9007199254740993,\"header_admit\":{\"us\":1,\"calls\":2,\"adv\":3}}"
    for (i = 1; i <= 1000; i++) print "{\"diagnostic\":0}"
}' > "$fixture/drive-response"
drive_response=$(cat "$fixture/drive-response")
check_drive "$drive_response" 'blocks total_us' 'header_admit' \
    '7,9007199254740993,1,2,3'
# With pipefail, a reader that exits early instead of draining its input must
# fail this large-response case if the printf producer receives SIGPIPE.
bash -o pipefail -ec '
    . "$1"
    response=$(cat "$2")
    for repeat in 1 2 3 4 5 6; do response="$response
$response"; done
    jnums "$response" "blocks total_us" "header_admit"
' bash "$fixture/drive.sh" "$fixture/drive-response" > "$fixture/drained.out"
[ "$(cat "$fixture/drained.out")" = '7,9007199254740993,1,2,3' ] || fail 'drained drive output'
# Instrument only the record-action loop (the initializer and END loops do
# not begin with eight spaces followed by an opening brace on its own line).
awk '
    /^        \{$/ {record=1}
    {print}
    record && /for \(i = 1;/ {print "                print \"column\" > \"/dev/stderr\""; record=0}
' "$fixture/drive.sh" > "$fixture/drive-counted.sh"
(
    . "$fixture/drive-counted.sh"
    jnums "$drive_response" 'blocks total_us' 'header_admit'
) > "$fixture/drive-counted.out" 2> "$fixture/columns"
[ "$(cat "$fixture/drive-counted.out")" = '7,9007199254740993,1,2,3' ] || fail 'counted drive output'
columns=$(wc -l < "$fixture/columns")
printf 'drive column-loop entries: %s (baseline 3003)\n' "$columns"
if [ "$bench" = 1 ]; then
    printf 'benchmark: 500 drive reads; fixture bytes: '
    wc -c < "$fixture/drive-response"
    time sh -ec '
        . "$1"
        response=$(cat "$2")
        i=0
        while [ "$i" -lt 500 ]; do
            result=$(jnums "$response" "blocks total_us" "header_admit")
            [ "$result" = "7,9007199254740993,1,2,3" ] || exit 1
            i=$((i + 1))
        done
    ' sh "$fixture/drive.sh" "$fixture/drive-response"
fi
[ "$columns" -eq 3 ] || fail "expected 3 drive column-loop entries, got $columns"
printf 'fold-profile drive scan selftest: PASS (values and bounded column scan)\n'

# Compact drive dumps can place requested fields after a long diagnostic
# prefix. Extract only matching fields, not the entire preceding document.
# Count actual matched bytes in a copy of the reader; timings stay uninstrumented.
awk 'BEGIN {
    printf "{"
    for (i = 1; i <= 10000; i++) printf "\"diagnostic_%d\":%d,", i, i
    print "\"blocks\":7,\"total_us\":9007199254740993,\"header_admit\":{\"us\":1,\"calls\":2,\"adv\":3}}"
}' > "$fixture/drive-prefix-response"
prefix_response=$(cat "$fixture/drive-prefix-response")
check_drive "$prefix_response" 'blocks total_us' 'header_admit' \
    '7,9007199254740993,1,2,3'
sed '/v = substr(/i\
                    print RLENGTH > "/dev/stderr"
' "$fixture/drive.sh" > "$fixture/drive-match-counted.sh"
(
    . "$fixture/drive-match-counted.sh"
    jnums "$prefix_response" 'blocks total_us' 'header_admit'
) > "$fixture/matched.out" 2> "$fixture/matched.bytes"
[ "$(cat "$fixture/matched.out")" = '7,9007199254740993,1,2,3' ] || fail 'matched drive output'
matched_bytes=$(awk '{total += $1} END {print total + 0}' "$fixture/matched.bytes")
printf 'drive matched bytes after diagnostic prefix: %s\n' "$matched_bytes"

# The last valid field wins, even when later occurrences are malformed or
# numeric prefixes only. Do not round, select the first duplicate, or retain
# state across columns/records. A delimiter consumed by one stage must not
# hide the next occurrence.
check_drive '{"blocks":1,"blocks":-0007.5,"blocks":null,"header_admit":{"us":1,"calls":2,"adv":3},"header_admit":{"us":4,"calls":5,"adv":6,"skips":0},"header_admit":{"us":7,"calls":8,"adv":null}}
{"blocks":99,"total_us":9007199254740993}' \
    'blocks total_us blocks absent' 'header_admit header_admit' \
    '-0007,9007199254740993,-0007,0,4,5,6,4,5,6'

if [ "$bench" = 1 ]; then
    printf 'benchmark: 100 drive reads after diagnostic prefix; fixture bytes: '
    wc -c < "$fixture/drive-prefix-response"
    time sh -ec '
        . "$1"
        response=$(cat "$2")
        i=0
        while [ "$i" -lt 100 ]; do
            result=$(jnums "$response" "blocks total_us" "header_admit")
            [ "$result" = "7,9007199254740993,1,2,3" ] || exit 1
            i=$((i + 1))
        done
    ' sh "$fixture/drive.sh" "$fixture/drive-prefix-response"
fi
[ "$matched_bytes" -gt 0 ] && [ "$matched_bytes" -le 100 ] || \
    fail "matched-field work budget: $matched_bytes bytes, expected 1..100"
printf 'fold-profile drive match selftest: PASS (values and bounded extraction)\n'

sh "$script_dir/fold_profile_boundary_selftest.sh" "$harness"
