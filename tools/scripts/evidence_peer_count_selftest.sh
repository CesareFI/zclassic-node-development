#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic peer-observer regression and cost benchmark; no node or network.
# Usage: bash tools/scripts/evidence_peer_count_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C
bench=0
case "${1:-}" in
    --bench) bench=1; shift ;;
    --selftest) shift ;;
esac
script_dir="$(cd "$(dirname "$0")" && pwd)"
library="${1:-$script_dir/lib/evidence_sources.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-evidence-peers.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
unset ZCL_EVIDENCE_SOURCES_SH_LOADED
# shellcheck source=tools/scripts/lib/evidence_sources.sh
. "$library"
failures=0

check() {
    local label="$1" input="$2" expected="$3" rc=0
    printf '%s' "$input" > "$fixture/input"
    evidence_peer_count_from_json < "$fixture/input" > "$fixture/actual" || rc=$?
    printf '%s\n' "$expected" > "$fixture/expected"
    if ! cmp -s "$fixture/actual" "$fixture/expected" || [ "$rc" -ne 0 ]; then
        printf '  FAIL: %s (status=%s, expected count=%s)\n' "$label" "$rc" "$expected"
        failures=$((failures + 1))
    else
        printf '  ok: %s\n' "$label"
    fi
}

check empty-input '' 0
check empty-list '[]' 0
check one-peer '[{"addr":"192.0.2.1:8033"}]' 1
check multiple-per-line '[{"addr":"192.0.2.1:8033"},{"addr":"[2001:db8::1]:8033"}]' 2
check pretty $'[\n {"addr" \t: "peer-a"},\n {"addr": "peer-b"}\n]\n' 2
check key-boundary '{"addrbind":"a","localaddr":"b","addr_hint":"c"}' 0
check whitespace $'{"addr"\r\t\v\f :"a"}' 1
# Preserve the old line-local key definition; this is not JSON validation.
check split-key $'{"addr"\n:"a"}' 0
check repeated-key '{"addr":"a","addr":"b","addr":"c"}' 3

input='['
for ((i=0; i<8192; i++)); do
    input+='{"addr":"192.0.2.1:8033"},'
done
input="${input%,}]"
check long-line "$input" 8192

# pipefail must still expose a failed upstream producer, even if it wrote a
# parseable prefix. The counter itself does not decide RPC success.
rc=0
(printf '%s' '[{"addr":"peer"}]'; exit 7) |
    evidence_peer_count_from_json > /dev/null || rc=$?
if [ "$rc" -ne 7 ]; then
    echo '  FAIL: upstream failure disappeared'
    failures=$((failures + 1))
fi

: > "$fixture/tools"
(
    grep() { echo grep >> "$fixture/tools"; command grep "$@"; }
    wc() { echo wc >> "$fixture/tools"; command wc "$@"; }
    tr() { echo tr >> "$fixture/tools"; command tr "$@"; }
    awk() { echo awk >> "$fixture/tools"; command awk "$@"; }
    evidence_peer_count_from_json <<< '[{"addr":"peer"}]' > /dev/null
)
tool_count="$(wc -l < "$fixture/tools")"
printf 'external text tools per observation: %s (baseline: 3)\n' "$tool_count"
if [ "$tool_count" -gt 1 ]; then
    echo '  FAIL: more than one counting process per observation'
    failures=$((failures + 1))
fi

if [ "$bench" = 1 ]; then
    input='['
    for ((i=0; i<64; i++)); do input+='{"addr":"192.0.2.1:8033"},'; done
    printf '%s' "${input%,}]" > "$fixture/peers"
    echo 'benchmark: 300 observations of a fixed 64-peer response, warm host caches'
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time (
        for ((i=0; i<300; i++)); do
            evidence_peer_count_from_json < "$fixture/peers" > /dev/null
        done
    )
fi
if [ "$failures" -ne 0 ]; then
    printf 'selftest: FAIL peer counter (%s failures)\n' "$failures" >&2
    exit 1
fi
echo 'selftest: PASS peer counter'
