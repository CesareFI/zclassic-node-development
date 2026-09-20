#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic integer-reader regression and optional polling-overhead benchmark.
# Run: bash tools/scripts/stopwatch_json_selftest.sh [--bench]
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/stopwatch_json_lib.sh"

check_read() {
    local description="$1" document="$2" key="$3" expected="$4" expected_rc="$5"
    local actual rc=0
    actual=$(jget "$document" "$key") || rc=$?
    if [ "$actual" != "$expected" ] || [ "$rc" != "$expected_rc" ]; then
        printf 'FAIL: %s: expected <%s> rc=%s, got <%s> rc=%s\n' \
            "$description" "$expected" "$expected_rc" "$actual" "$rc" >&2
        exit 1
    fi
}

check_read 'height' '{"hstar":3107923}' hstar 3107923 0
check_read 'zero' '{"hstar":0}' hstar 0 0
check_read 'negative sentinel' '{"cached_provable_tip":-1}' cached_provable_tip -1 0
check_read 'wide counter stays text' '{"download_bytes_received":18446744073709551615}' \
    download_bytes_received 18446744073709551615 0
check_read 'whitespace' $'{ "hstar" \t: \t42 }' hstar 42 0
check_read 'multiline document' $'{\n "hstar": 42\n}' hstar 42 0
check_read 'similar field names' '{"hstar_next_height":999,"hstar":42}' hstar 42 0
check_read 'boolean suffix' '{"network_tip_read_ok":true,"network_tip":456}' network_tip 456 0
check_read 'first occurrence' '{"hstar":42,"hstar":99}' hstar 42 0
check_read 'empty response' '' hstar '' 1
check_read 'missing field' '{"hstar_next_height":999}' hstar '' 1
check_read 'null field' '{"hstar":null}' hstar '' 1
check_read 'string field' '{"hstar":"42"}' hstar '' 1
check_read 'boolean field' '{"hstar":true}' hstar '' 1

# Prove the hot path needs no external executables. This fails for the former
# printf | grep | head | grep pipeline even when its output checks pass.
(
    PATH=/nonexistent
    check_read 'no subprocess tools' '{"hstar":42}' hstar 42 0
)
printf 'stopwatch-json: PASS (15 checks)\n'

case "${1:-}" in
    '') exit 0 ;;
    --bench) ;;
    *) printf 'usage: %s [--bench]\n' "$0" >&2; exit 2 ;;
esac

# Retain the old reader here only as a benchmark reference. Time the same
# command-substitution call pattern as the real poller, including its subshell.
jget_pipeline_reference() {
    printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*-?[0-9]+" | head -1 |
        grep -oE -- '-?[0-9]+$'
}
fixture='{"cached_provable_tip":3107000,"hstar":3107923,"network_tip":3190019,"network_tip_read_ok":true}'
for reader in jget_pipeline_reference jget; do
    TIMEFORMAT="$reader: 900 field reads in %3R seconds"
    time for ((i=0; i<300; i++)); do
        for key in hstar network_tip cached_provable_tip; do
            value=$("$reader" "$fixture" "$key")
            [ -n "$value" ]
        done
    done
done
