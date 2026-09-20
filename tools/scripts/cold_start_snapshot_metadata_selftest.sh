#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Fixture selection and metadata-process budget; never starts a node.
# Usage: bash tools/scripts/cold_start_snapshot_metadata_selftest.sh [--cold-start] [--bench] [source.sh]
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
bench=0
cold_start=0
if [[ "${1:-}" == --cold-start ]]; then cold_start=1; shift; fi
if [[ "${1:-}" == --bench ]]; then bench=1; shift; fi
source_file="${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}"
. "$root/tools/scripts/stopwatch_json_lib.sh"
if [[ "$cold_start" == 1 && $# == 0 ]]; then source_file="$root/tools/scripts/cold_start_test.sh"; fi
fixture="$(mktemp -d /tmp/z23-snapshot-metadata.XXXXXX)"
trap 'rm -rf "$fixture"' EXIT
if [[ "$cold_start" == 1 ]]; then
    # Exercise the cold-start gate's inline selector without its node launch,
    # copying or cleanup. Reuse the same fixture contract as the tip probe.
    awk '/^if \[ -z "\$SRC_BUNDLE_SNAP" \]; then/ {copy=1}
         copy {print} copy && /^fi$/ {exit}' "$source_file" > "$fixture/inline.sh"
    [[ -s "$fixture/inline.sh" ]]
    cat > "$fixture/selector.sh" <<'SH'
select_newest_bundle_snapshot() {
    local SRC_BUNDLE_SNAP="${snapshot_override:-}"
    local -a SRC_BUNDLE_SNAP_CANDIDATES=("${BUNDLE_SNAP_CANDIDATES[@]}")
    . "$fixture/inline.sh"
    printf '%s\n' "$SRC_BUNDLE_SNAP"
}
SH
else
awk '/^probe_file_metadata\(\)|^select_newest_bundle_snapshot\(\)/ {copy=1}
     copy {print} copy && /^}/ {copy=0}' "$source_file" > "$fixture/selector.sh"
fi
. "$fixture/selector.sh"
declare -F select_newest_bundle_snapshot >/dev/null

# Count actual metadata commands, including commands inside substitutions.
stat() {
    printf 'stat\n' >> "$fixture/calls"
    [[ "${*: -1}" != "$fixture/refused" ]] || return 1
    command stat "$@"
}
check() {
    local name="$1" want="$2" got
    got="$(select_newest_bundle_snapshot)"
    [[ "$got" == "$want" ]] || {
        printf 'FAIL: %s selected <%s>, expected <%s>\n' "$name" "$got" "$want" >&2
        exit 1
    }
}

floor=$((10 * 1024 * 1024))
for name in old 'new snapshot' tie small boundary refused epoch; do
    truncate -s "$((floor + 1))" "$fixture/$name"
done
truncate -s "$floor" "$fixture/boundary"
truncate -s 0 "$fixture/small"
touch -d @100 "$fixture/old"
touch -d @200 "$fixture/new snapshot" "$fixture/tie"
touch -d @0 "$fixture/epoch"
: > "$fixture/calls"
BUNDLE_SNAP_CANDIDATES=("$fixture/missing" "$fixture/small" "$fixture/boundary" "$fixture/refused")
check ineligible ''
BUNDLE_SNAP_CANDIDATES=("$fixture/epoch")
check epoch "$fixture/epoch"
BUNDLE_SNAP_CANDIDATES=("$fixture/new snapshot" "$fixture/old")
check newest "$fixture/new snapshot"
BUNDLE_SNAP_CANDIDATES=("$fixture/new snapshot" "$fixture/tie")
check last-tie "$fixture/tie"
BUNDLE_SNAP_CANDIDATES=("$fixture/tie" "$fixture/new snapshot")
check reversed-tie "$fixture/new snapshot"
BUNDLE_SNAP_CANDIDATES=()
check empty ''
if [[ "$cold_start" == 1 ]]; then
    snapshot_override="$fixture/explicit snapshot"
    BUNDLE_SNAP_CANDIDATES=("$fixture/new snapshot")
    : > "$fixture/calls"
    check override "$snapshot_override"
    [[ ! -s "$fixture/calls" ]]
    unset snapshot_override
    echo 'PASS: explicit snapshot bypasses selection and metadata commands'
fi
printf 'PASS: size floor, missing/refused metadata, epoch, newest, spaces, tie order, empty list\n'

BUNDLE_SNAP_CANDIDATES=()
for ((i=0; i<100; i++)); do
    candidate="$fixture/snapshot-$i"
    truncate -s "$((floor + 1))" "$candidate"
    touch -d "@$((1000 + i))" "$candidate"
    BUNDLE_SNAP_CANDIDATES+=("$candidate")
done
: > "$fixture/calls"
if [[ "$bench" == 1 ]]; then
    TIMEFORMAT='ten_selections_seconds=%3R user=%3U system=%3S'
    time for ((i=0; i<10; i++)); do check many "$fixture/snapshot-99"; done
else
    check many "$fixture/snapshot-99"
fi
calls="$(wc -l < "$fixture/calls")"
expected=100
[[ "$bench" == 0 ]] || expected=1000
printf 'metadata_commands=%s expected=%s\n' "$calls" "$expected"
[[ "$calls" == "$expected" ]] || {
    echo 'FAIL: selector must read size and mtime in one metadata command per candidate' >&2
    exit 1
}
echo 'PASS: one metadata command per candidate'
