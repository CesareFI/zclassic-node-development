#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# RSS observer regression and cost benchmark; no node, network or datadir.
# Usage: bash tools/scripts/evidence_rss_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C

bench=0
case "${1:-}" in
    --bench) bench=1; shift ;;
    --selftest) shift ;;
esac
script_dir="$(cd "$(dirname "$0")" && pwd)"
library="${1:-$script_dir/lib/evidence_sources.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-evidence-rss.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
unset ZCL_EVIDENCE_SOURCES_SH_LOADED
# shellcheck source=tools/scripts/lib/evidence_sources.sh
. "$library"

# Exercise the actual reader with only its /proc root redirected to fixtures.
# No production override is introduced for the process-memory evidence source.
reader="$(declare -f evidence_rss_kb)"
case "$reader" in
    */proc/*) ;;
    *) echo 'selftest: FAIL RSS reader no longer uses /proc' >&2; exit 1 ;;
esac
reader=${reader//\/proc\//\$fixture\/proc\/}
eval "$reader"
mkdir -p "$fixture/proc/123"
failures=0

check() {
    local label="$1" status="$2" expected="$3"
    printf '%s' "$status" > "$fixture/proc/123/status"
    if ! evidence_rss_kb 123 > "$fixture/actual" 2> "$fixture/stderr"; then
        printf '  FAIL: %s returned nonzero for a missing observation\n' "$label" >&2
        failures=$((failures + 1))
    fi
    printf '%s' "$expected" > "$fixture/expected"
    cmp "$fixture/expected" "$fixture/actual"
    test ! -s "$fixture/stderr"
    printf '  bytes match: %s\n' "$label"
}

status=$'Name:\tfixture\nState:\tS (sleeping)\nVmPeak:\t99999 kB\nVmRSS:\t   123456 kB\nRssAnon:\t123000 kB\nThreads:\t1\n'
check ordinary "$status" $'123456\n'
check zero $'VmRSS:\t0 kB\n' $'0\n'
check whitespace $'VmRSS:   42\tkB\n' $'42\n'
check wide-integer $'VmRSS:\t18446744073709551615 kB\n' $'18446744073709551615\n'
check absent-field $'Name:\tkernel-thread\nThreads:\t1\n' ''
check empty '' ''
check invalid-number $'VmRSS:\tunknown kB\n' ''
check wrong-unit $'VmRSS:\t42 MB\n' ''

# The reader must split kernel whitespace even when its caller changes IFS.
( IFS=:; check caller-ifs "$status" $'123456\n' )

# Exercise the open/read failure path without requiring process-race timing.
rm "$fixture/proc/123/status"
mkdir "$fixture/proc/123/status"
if ! evidence_rss_kb 123 > "$fixture/actual" 2> "$fixture/stderr"; then
    echo '  FAIL: failed status read returned nonzero' >&2
    failures=$((failures + 1))
fi
test ! -s "$fixture/actual"
test ! -s "$fixture/stderr"
rmdir "$fixture/proc/123/status"
echo '  bytes match: failed status read is empty'

for pid in '' 0 -1 abc '123/../123' 999; do
    evidence_rss_kb "$pid" > "$fixture/actual" 2> "$fixture/stderr"
    test ! -s "$fixture/actual"
    test ! -s "$fixture/stderr"
done
echo '  ok: invalid and missing PIDs return an empty observation'

# Deterministic process budget independent of wall time and host load.
printf '%s' "$status" > "$fixture/proc/123/status"
: > "$fixture/tools"
(
    grep() { echo grep >> "$fixture/tools"; command grep "$@"; }
    sed() { echo sed >> "$fixture/tools"; command sed "$@"; }
    head() { echo head >> "$fixture/tools"; command head "$@"; }
    test "$(evidence_rss_kb 123)" = 123456
)
tool_count="$(wc -l < "$fixture/tools")"
printf 'external text tools per RSS sample: %s (baseline: 3)\n' "$tool_count"

if [ "$bench" = 1 ]; then
    echo 'benchmark: 500 RSS reads, fixed status fixture, warm host caches'
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time (
        for ((i=0; i<500; i++)); do
            test "$(evidence_rss_kb 123)" = 123456
        done
    )
fi
if [ "$tool_count" -ne 0 ]; then
    echo 'selftest: FAIL RSS sampling still starts external text tools' >&2
    exit 1
fi
test "$failures" -eq 0
# A successful read must also work with no external commands available.
test "$(PATH=/nonexistent evidence_rss_kb 123)" = 123456
echo 'selftest: PASS RSS observer'
