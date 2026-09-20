#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure bundle-height parsing in the shipped selector, without a node.
# Usage: bash tools/scripts/cold_start_bundle_height_selftest.sh [--baseline] [probe.sh]
set -euo pipefail
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
subject=${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}
fixture=$(mktemp -d /tmp/z23-bundle-height.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
fail() { printf 'bundle height: FAIL: %s\n' "$*" >&2; exit 1; }
awk '/^consensus_bundle_height\(\)|^select_newest_consensus_bundle\(\)/ {copy=1}
     copy {print} copy && /^}/ {copy=0}' "$subject" |
    sed 's/^consensus_bundle_height()/fixture_height()/' > "$fixture/select.sh"
. "$fixture/select.sh"
declare -F fixture_height >/dev/null
declare -F select_newest_consensus_bundle >/dev/null
selector_pid=$BASHPID
consensus_bundle_height() {
    printf 'call\n' >> "$fixture/calls"
    if [[ $BASHPID != "$selector_pid" ]]; then
        printf 'fork\n' >> "$fixture/forks"
    fi
    fixture_height "$@"
}
mkdir "$fixture/catalog"
floor=$((10 * 1024 * 1024))
CONSENSUS_BUNDLE_CANDIDATES=()
for ((i = 100; i > 0; i--)); do
    path="$fixture/catalog/consensus-state-bundle-$i.sqlite"
    truncate -s "$((floor + 1))" "$path"
    CONSENSUS_BUNDLE_CANDIDATES+=("$path")
done
: > "$fixture/calls"
: > "$fixture/forks"
TIMEFORMAT='selection_wall_seconds=%3R user=%3U system=%3S'
for ((trial = 1; trial <= 3; trial++)); do
    printf 'trial=%d selections=5 candidates=100\n' "$trial"
    time for ((repeat = 0; repeat < 5; repeat++)); do
        select_newest_consensus_bundle > "$fixture/winner"
        actual=$(< "$fixture/winner")
        [[ $actual == "${CONSENSUS_BUNDLE_CANDIDATES[0]}" ]] || fail 'winner changed'
    done
done
calls=$(wc -l < "$fixture/calls")
forks=$(wc -l < "$fixture/forks")
printf 'height_calls=%s child_shell_calls=%s\n' "$calls" "$forks"
[[ $calls == 1500 ]] || fail 'height parser was not exercised'
if (( baseline )); then exit 0; fi
[[ $forks == 0 ]] || fail 'height parsing forked a child shell'

# The parser assigns the requested output without printing or altering a
# neighboring variable. Noncanonical names retain their fallback rank.
check_height() {
    local name=$1 expected=$2 result=stale untouched=keep
    consensus_bundle_height "$name" result > "$fixture/output"
    [[ $result == "$expected" && $untouched == keep && ! -s "$fixture/output" ]] ||
        fail "height result for <$name>"
}
check_height consensus-state-bundle-0.sqlite 0
check_height consensus-state-bundle-3056758.sqlite 3056758
check_height consensus-state-bundle-0009.sqlite 0009
check_height consensus-state-bundle-.sqlite -1
check_height consensus-state-bundle-x.sqlite -1
check_height consensus-state-bundle-9.sqlite.extra -1
check_height fallback.sqlite -1
printf 'PASS: height parsing stays in the selector process and preserves ranks\n'
