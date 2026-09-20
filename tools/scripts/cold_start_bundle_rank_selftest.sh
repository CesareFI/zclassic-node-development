#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Bundle-selection semantics and metadata demand; no node or real datadir.
# Usage: bash tools/scripts/cold_start_bundle_rank_selftest.sh [--bench] [probe.sh]
set -euo pipefail
bench=0
if [[ "${1:-}" == --bench ]]; then bench=1; shift; fi
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
subject=${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}
fixture=$(mktemp -d /tmp/z23-bundle-rank.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
fail() { printf 'bundle rank: FAIL: %s\n' "$*" >&2; exit 1; }
awk '/^consensus_bundle_height\(\)|^select_newest_consensus_bundle\(\)/ {copy=1}
     copy {print} copy && /^}/ {copy=0}' "$subject" > "$fixture/select.sh"
. "$fixture/select.sh"
declare -F consensus_bundle_height >/dev/null
declare -F select_newest_consensus_bundle >/dev/null
mkdir "$fixture/first" "$fixture/second"
floor=$((10 * 1024 * 1024))
for name in consensus-state-bundle-9.sqlite consensus-state-bundle-100.sqlite \
            consensus-state-bundle-3056758.sqlite fallback.sqlite 'z fallback.sqlite' \
            boundary.sqlite refused.sqlite wrong.txt; do
    truncate -s "$((floor + 1))" "$fixture/first/$name"
done
truncate -s "$floor" "$fixture/first/boundary.sqlite"
truncate -s "$((floor + 1))" "$fixture/second/consensus-state-bundle-100.sqlite"
stat() {
    printf 'stat\n' >> "$fixture/calls"
    [[ "${*: -1}" != "$fixture/first/refused.sqlite" ]] || return 1
    command stat "$@"
}
check() {
    local label=$1 expected=$2 actual
    shift 2
    CONSENSUS_BUNDLE_CANDIDATES=("$@")
    actual=$(select_newest_consensus_bundle)
    [[ "$actual" == "$expected" ]] || fail "$label: expected <$expected>, got <$actual>"
}
a="$fixture/first/consensus-state-bundle-9.sqlite"
b="$fixture/first/consensus-state-bundle-100.sqlite"
c="$fixture/first/consensus-state-bundle-3056758.sqlite"
tie="$fixture/second/consensus-state-bundle-100.sqlite"
check empty ''
check ineligible '' "$fixture/missing" "$fixture/first/boundary.sqlite" \
    "$fixture/first/refused.sqlite" "$fixture/first/wrong.txt" "$fixture/first"
check ascending "$c" "$a" "$b" "$c"
check descending "$c" "$c" "$b" "$a"
check mixed "$c" "$b" "$a" "$c"
check first-tie "$b" "$b" "$tie"
check reverse-tie "$tie" "$tie" "$b"
check fallback "$fixture/first/z fallback.sqlite" \
    "$fixture/first/fallback.sqlite" "$fixture/first/z fallback.sqlite"
check canonical "$a" "$fixture/first/z fallback.sqlite" "$a"
: > "$c.failed"
check failed-high "$b" "$c" "$a" "$b"
rm "$c.failed"
truncate -s "$floor" "$c"
check undersized-high-first "$b" "$c" "$a" "$b"
check undersized-high-last "$b" "$a" "$b" "$c"
truncate -s 0 "$b"
check undersized-first-tie "$tie" "$b" "$tie"
truncate -s "$((floor + 1))" "$b" "$c"
check failed-metadata-fallback "$fixture/first/fallback.sqlite" \
    "$fixture/first/refused.sqlite" "$fixture/first/fallback.sqlite"
printf 'PASS: 14 selection scenarios\n'

# A recently selected high bundle precedes a retained older catalog. Only
# possible winners need a size command. Ascending catalogs still read each.
CONSENSUS_BUNDLE_CANDIDATES=("$c")
for ((i = 200; i > 101; i--)); do
    path="$fixture/first/consensus-state-bundle-$i.sqlite"
    truncate -s "$((floor + 1))" "$path"
    CONSENSUS_BUNDLE_CANDIDATES+=("$path")
done
: > "$fixture/calls"
runs=1
[[ "$bench" == 0 ]] || runs=10
TIMEFORMAT='selection_wall_seconds=%3R user=%3U system=%3S'
time for ((iteration = 0; iteration < runs; iteration++)); do
    got=$(select_newest_consensus_bundle)
    [[ "$got" == "$c" ]] || fail 'catalog winner changed'
done
calls=$(wc -l < "$fixture/calls")
printf 'metadata_commands=%s expected=%s (100 candidates per selection)\n' "$calls" "$runs"
[[ "$calls" == "$runs" ]] || fail 'read metadata for candidates that cannot win'
printf 'PASS: metadata demand\n'
