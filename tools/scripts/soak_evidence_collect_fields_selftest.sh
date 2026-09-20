#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Hermetic collect-field regression and observer process-budget benchmark.
# Usage: bash tools/scripts/soak_evidence_collect_fields_selftest.sh [--baseline] [script]
set -euo pipefail
export LC_ALL=C

baseline=0
if [ "${1:-}" = --baseline ]; then
    baseline=1
    shift
fi
script_dir="$(cd "$(dirname "$0")" && pwd)"
subject="${1:-$script_dir/soak_evidence.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-soak-fields.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { echo "FAIL: $*" >&2; exit 1; }

export ZCL_SOAK_EVIDENCE_DIR="$fixture/evidence"
export ZCL_SOAK_RPC_CMD="printf '{\"result\":bad}\\n{\"result\":101}'"
export ZCL_ZD_RPC_CMD="printf '{\"result\":100,\"result\":101,\"result\":bad}'"
export ZCL_SOAK_SECURITY_CMD="printf '{\"security_review_required\":null}\\n{\"security_review_required\" : false}'"
export ZCL_SOAK_SHOW_CMD="printf 'NRestarts=bad\\nNRestarts=7\\nActiveEnterTimestamp=\\nActiveEnterTimestamp=Fri 2026-09-18 12:00:00 UTC\\nMainPID=x\\nMainPID=4242\\n'"
export ZCL_SOAK_RSS_CMD="printf 'VmRSS: 8192 kB VmRSS: bad kB\\n'"
export ZCL_SOAK_NOW=1789732800
export ZCL_SOAK_FIELD_TOOL_LOG="$fixture/tools"
: > "$ZCL_SOAK_FIELD_TOOL_LOG"

# Count only the parser processes whose implementation this regression
# constrains. Delegating to the real tools keeps the complete collector live.
sed() { echo sed >> "$ZCL_SOAK_FIELD_TOOL_LOG"; command sed "$@"; }
head() { echo head >> "$ZCL_SOAK_FIELD_TOOL_LOG"; command head "$@"; }
grep() { echo grep >> "$ZCL_SOAK_FIELD_TOOL_LOG"; command grep "$@"; }
export -f sed head grep

bash "$subject" collect > "$fixture/out"
line="$(tail -n 1 "$fixture/out")"
case "$line" in
    *'"nrestarts":7'*'"active_enter_ts":1789732800'*'"rss_kb":8192'*'"mainpid":4242'*) ;;
    *) fail "collector changed service-field values: $line" ;;
esac
sed_calls=0
head_calls=0
grep_calls=0
while IFS= read -r tool; do
    case "$tool" in
        sed) sed_calls=$((sed_calls + 1)) ;;
        head) head_calls=$((head_calls + 1)) ;;
        grep) grep_calls=$((grep_calls + 1)) ;;
    esac
done < "$ZCL_SOAK_FIELD_TOOL_LOG"
total=$((sed_calls + head_calls + grep_calls))
printf 'service sample field-parser processes=%s (sed=%s head=%s grep=%s; prior=15)\n' \
    "$total" "$sed_calls" "$head_calls" "$grep_calls"
if [ "$baseline" -eq 0 ] && [ "$total" -gt 0 ]; then
    fail 'already-fetched scalar fields still start text-tool parsers'
fi

# Missing and malformed service fields remain JSON null, never fabricated 0.
: > "$ZCL_SOAK_FIELD_TOOL_LOG"
export ZCL_SOAK_SHOW_CMD="printf 'NRestarts=bad\\nActiveEnterTimestamp=\\nMainPID=x\\n'"
bash "$subject" collect > "$fixture/missing"
line="$(tail -n 1 "$fixture/missing")"
case "$line" in
    *'"nrestarts":null'*'"active_enter_ts":null'*'"rss_kb":8192'*'"mainpid":null'*) ;;
    *) fail "malformed service fields did not stay unknown: $line" ;;
esac

echo 'PASS: service/RPC/RSS fields preserve values without text-tool parser processes'
