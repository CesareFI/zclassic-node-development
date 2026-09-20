#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Read-only sync diagnostics: output parity and deterministic parser-byte budget.
# Usage: JSONQ=/path/to/jsonq bash tools/scripts/debug_bundle_triage_selftest.sh [script]
# TRIAGE_REFERENCE=/path/to/old-script enables exact old/new report comparison.
# TRIAGE_BENCH=1 also times five uninstrumented large-bundle reports.
set -euo pipefail
export LC_ALL=C
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
triage=${1:-$script_dir/debug_bundle_triage.sh}
jsonq=${JSONQ:-$script_dir/../../build/bin/jsonq}
[[ -x $jsonq ]] || { echo 'selftest: build jsonq first' >&2; exit 2; }
fixture=$(mktemp -d /tmp/z23-triage-test.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$fixture/small" "$fixture/large"
cat > "$fixture/fields" <<'JSON'
"format":"zcl.debug_bundle.v1","captured_at_utc":"fixture",
"build":{"version":"test","build_commit":"abcdef","source_id_sha256":"123456"},
"subsystems":{
 "reducer_frontier":{"hstar":42,"served_floor":40,"served_gap":2,
 "network_tip_read_ok":true,"network_tip":50,"hstar_to_network_tip_gap":8,
 "cached_provable_tip":41,"hstar_next_blocked":true,
 "hstar_next_primary_stage":"body_fetch","hstar_next_primary_kind":"pending",
 "hstar_next_primary_detail":"fixture only","hstar_next_primary_repair_owner":"observer",
 "coins_best_height":41},
 "blocker":{"active_count":1,"permanent_count":0,"dependency_count":1,
 "transient_count":0,"resource_count":0,"blockers":[{"id":"fixture",
 "owner":"observer","class":"dependency","age_us":2000000,"fire_count":3,
 "reason":"quoted \"text\" and backslash \\","caused_by":"fixture","cause_detail":"detail"}]},
 "sovereignty":{"trust_mode":"sovereign","self_folded_marker":true,
 "coins_kv_proven_authority":false,"self_derived_tip_static_checks":false,
 "self_derived_reason":"fixture"}},
"supervisor_stalls":{"child_count":1,"stalled_or_fired_count":1,
 "children":[{"name":"fixture","stall_reason":"pending","stall_fires":1,
 "last_tick_age_us":3000000,"progress_marker":42}]}
JSON
{ printf '{'; cat "$fixture/fields"; printf '}\n'; } > "$fixture/small/bundle.json"
{
    printf '{"unrelated_dump":"'
    awk 'BEGIN { for (i=0; i<16384; i++) printf "%064d", 0 }'
    printf '",'; cat "$fixture/fields"; printf '}\n'
} > "$fixture/large/bundle.json"
JSONQ="$jsonq" bash "$triage" "$fixture/small/bundle.json" > "$fixture/expected"
grep -Fq 'H*=42 served_floor=40 gap=2 provable_tip=41  network_tip=50 tail_gap=8' "$fixture/expected"
grep -Fq 'H*+1 BLOCKED stage=body_fetch kind=pending detail=fixture only' "$fixture/expected"
grep -Fq 'reason: quoted "text" and backslash \' "$fixture/expected"
grep -Fq 'children=1 stalled_or_fired=1' "$fixture/expected"
if [[ -n ${TRIAGE_REFERENCE:-} ]]; then
    JSONQ="$jsonq" bash "$TRIAGE_REFERENCE" "$fixture/small/bundle.json" > "$fixture/reference"
    cmp "$fixture/expected" "$fixture/reference"
fi

# Measure bytes actually supplied to the real parser, independent of host load.
cat > "$fixture/jsonq-meter" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
input=$(mktemp "$TRIAGE_FIXTURE/input.XXXXXX")
trap 'rm -f "$input"' EXIT
cat > "$input"
wc -c < "$input" >> "$TRIAGE_FIXTURE/bytes"
"$TRIAGE_JSONQ" "$@" < "$input"
SH
chmod +x "$fixture/jsonq-meter"
TRIAGE_FIXTURE="$fixture" TRIAGE_JSONQ="$jsonq" JSONQ="$fixture/jsonq-meter" \
    bash "$triage" "$fixture/large/bundle.json" > "$fixture/actual"
cmp "$fixture/expected" "$fixture/actual"
bytes=$(awk '{ n += $1 } END { printf "%.0f", n }' "$fixture/bytes")
size=$(wc -c < "$fixture/large/bundle.json")
printf 'parser input: %s bytes for %s-byte bundle\n' "$bytes" "$size"

for body in '{"format":"zcl.debug_bundle.v1","subsystems":{}}' \
    '{"format":"zcl.debug_bundle.v1","subsystems":{"reducer_frontier":{"error":"unavailable"},"blocker":{"error":"unavailable"}}}' \
    '{"format":"zcl.debug_bundle.v1","trigger":"supervisor","trigger_child":"fixture","trigger_stall_reason":"pending","build":null,"subsystems":{"blocker":{"blockers":[{"id":"a"},{"id":"b"},{"id":"c"},{"id":"d"},{"id":"e"},{"id":"f"}]}},"supervisor_stalls":{"children":[{"name":"first"},{"name":"second"}]}}' \
    '{"format":"zcl.debug_bundle.v1","subsystems":{"reducer_frontier":null,"blocker":null,"sovereignty":null},"supervisor_stalls":null}'; do
    printf '%s\n' "$body" > "$fixture/bundle.json"
    JSONQ="$jsonq" bash "$triage" "$fixture/bundle.json" > "$fixture/result"
    grep -Fq '== frontier ==' "$fixture/result"
    if [[ $body == *'"trigger":"supervisor"'* ]]; then
        grep -Fq 'trigger=supervisor child=fixture reason=pending' "$fixture/result"
        grep -Fq '... and 1 more' "$fixture/result"
        grep -Fq '  - second reason=' "$fixture/result"
        if grep -Fq '  - f owner=' "$fixture/result"; then
            echo 'FAIL: blocker display limit was lost' >&2; exit 1
        fi
    fi
    if [[ -n ${TRIAGE_REFERENCE:-} ]]; then
        JSONQ="$jsonq" bash "$TRIAGE_REFERENCE" "$fixture/bundle.json" > "$fixture/reference"
        cmp "$fixture/result" "$fixture/reference"
    fi
done
if [[ ${TRIAGE_BENCH:-0} = 1 ]]; then
    TIMEFORMAT='five warm reports: %3R s wall, %3U s user, %3S s system'
    time for ((i=0; i<5; i++)); do
        JSONQ="$jsonq" bash "$triage" "$fixture/large/bundle.json" > /dev/null
    done
fi
for body in '{}' '{"format":"zcl.debug_bundle.v1","subsystems":{}} trailing' \
    '{"format":"zcl.debug_bundle.v1"}'; do
    printf '%s\n' "$body" > "$fixture/bundle.json"
    if JSONQ="$jsonq" bash "$triage" "$fixture/bundle.json" > /dev/null 2>&1; then
        echo 'FAIL: malformed or incomplete bundle accepted' >&2; exit 1
    fi
done
if (( bytes > size * 16 )); then
    echo 'FAIL: repeated full-bundle parsing exceeds 16 bundle lengths' >&2
    exit 1
fi
echo 'debug bundle triage selftest: PASS'
