#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Bundle catalog selection must not spawn a basename process per candidate.
# Usage: bash tools/scripts/cold_start_bundle_name_selftest.sh [--baseline] [probe.sh]
set -euo pipefail
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
subject=${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}
fixture=$(mktemp -d /tmp/z23-bundle-name.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
fail() { printf 'bundle name: FAIL: %s\n' "$*" >&2; exit 1; }
awk '/^consensus_bundle_height\(\)|^select_newest_consensus_bundle\(\)/ {copy=1}
     copy {print} copy && /^}/ {copy=0}' "$subject" > "$fixture/select.sh"
. "$fixture/select.sh"
declare -F consensus_bundle_height >/dev/null
declare -F select_newest_consensus_bundle >/dev/null

# Exercise real sparse files and metadata, with no node, network or datadir.
catalog="$fixture/space and [glob]"$'\n'"directory"
mkdir "$catalog"
floor=$((10 * 1024 * 1024))
for name in 'fallback space.sqlite' '-leading.sqlite' '[glob].sqlite' \
            $'embedded\nnewline.sqlite'; do
    truncate -s "$((floor + 1))" "$catalog/$name"
done
basename() {
    printf 'basename\n' >> "$fixture/calls"
    command basename "$@"
}
check() {
    local expected=$1 actual
    shift
    CONSENSUS_BUNDLE_CANDIDATES=("$@")
    actual=$(select_newest_consensus_bundle)
    [[ $actual == "$expected" ]] || fail "selection differs for <$expected>"
}
for path in "$catalog"/*.sqlite; do
    check "$path" "$path"
done
check '' "$catalog/missing.sqlite" "$catalog/"

CONSENSUS_BUNDLE_CANDIDATES=()
for ((i = 100; i > 0; i--)); do
    path="$catalog/consensus-state-bundle-$i.sqlite"
    truncate -s "$((floor + 1))" "$path"
    CONSENSUS_BUNDLE_CANDIDATES+=("$path")
done
winner="$catalog/consensus-state-bundle-100.sqlite"
: > "$fixture/calls"
TIMEFORMAT='selection_wall_seconds=%3R user=%3U system=%3S'
for ((trial = 1; trial <= 3; trial++)); do
    printf 'trial=%d selections=5 candidates=100\n' "$trial"
    time for ((repeat = 0; repeat < 5; repeat++)); do
        actual=$(select_newest_consensus_bundle)
        [[ $actual == "$winner" ]] || fail 'catalog winner changed'
    done
done
calls=$(wc -l < "$fixture/calls")
printf 'basename_commands=%s\n' "$calls"
if (( baseline )); then
    printf 'BASELINE: selection and process demand measured\n'
else
    [[ $calls == 0 ]] || fail 'spawned basename while selecting bundles'
    printf 'PASS: bundle names preserved with no basename processes\n'
fi
