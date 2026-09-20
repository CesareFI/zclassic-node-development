#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise only the fresh-boot observer, never its datadir/launch machinery.
# Usage: bash tools/scripts/fresh_boot_frontier_selftest.sh [--bench] [harness]
set -uo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject=${1:-$script_dir/fresh-boot-proof.sh}
fixture=$(mktemp -d /tmp/z23-fresh-frontier.XXXXXX) || exit 1
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sed -n '/^rpc_frontier() {/,/^}/p' "$subject" > "$fixture/reader.sh"
. "$fixture/reader.sh"
declare -F rpc_frontier >/dev/null || { echo 'missing rpc_frontier' >&2; exit 1; }

# Persist counts across the reader's command substitution. All RPCs are local
# fixture reads; backoff is counted rather than slept.
rpc() {
    local count
    read -r count < "$fixture/calls"
    printf '%s\n' "$((count + 1))" > "$fixture/calls"
    if [[ $mode == repeat || $count == 0 ]]; then printf '%s' "$response"; fi
    return 0
}
sleep() { delay=$((delay + $1)); }
grep() { printf 'grep\n' >> "$fixture/parsers"; command grep "$@"; }
failed=0
check() {
    local label=$1 expected_calls=$2 expected_delay=$3 expected=$4 calls
    delay=0
    printf '0\n' > "$fixture/calls"
    rpc_frontier > "$fixture/actual"
    read -r calls < "$fixture/calls"
    printf '%s' "$expected" > "$fixture/expected"
    if [[ $calls != "$expected_calls" || $delay != "$expected_delay" ]] ||
       ! cmp -s "$fixture/actual" "$fixture/expected"; then
        printf 'FAIL pipefail=%s %s: calls=%s delay=%ss (want %s/%ss); response bytes checked\n' \
            "$pipe_mode" "$label" "$calls" "$delay" "$expected_calls" "$expected_delay" >&2
        failed=1
    else
        printf 'PASS pipefail=%s %s: calls=%s delay=%ss\n' \
            "$pipe_mode" "$label" "$calls" "$delay"
    fi
}

printf -v padding '%1048576s' ''
: > "$fixture/parsers"
# The manual harness sets only nounset, but may inherit pipefail via SHELLOPTS.
# Require identical observations in both configurations.
for pipe_mode in off on; do
    if [[ $pipe_mode == on ]]; then set -o pipefail; else set +o pipefail; fi
    mode=repeat
    response='{"hstar":123,"network_tip":456}'
    check small 1 0 "$response"
    for mode in repeat once; do
        response=$'{"hstar":123,\n"padding":"'"$padding"'"}'
        check "large early match ($mode)" 1 0 "$response"
    done
    mode=repeat
    response='{"padding":"'"$padding"$'",\n"hstar":123}'
    check 'large late match' 1 0 "$response"
    response='{"snapshot_status":"progress_store_busy","retryable":true}'
    check busy 4 4 "$response"
    mode=once
    check 'partial followed by empty' 4 4 ''
    mode=repeat
    response='{"cached_hstar":123,"hstar_next_height":124}'
    check 'similar keys' 4 4 "$response"
    response=''
    check empty 4 4 ''
done
parser_count=$(wc -l < "$fixture/parsers")
printf 'external matchers across fixture observations: %s (required 0)\n' "$parser_count"
if [[ $parser_count -ne 0 ]]; then failed=1; fi

if (( bench )); then
    mode=repeat
    response='{"hstar":123,"network_tip":456}'
    printf '0\n' > "$fixture/calls"
    delay=0
    TIMEFORMAT='200 fixture frontier reads: wall=%3R user=%3U sys=%3S seconds'
    time for ((i=0; i<200; i++)); do rpc_frontier > /dev/null; done
fi
exit "$failed"
