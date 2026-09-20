#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Usage: bash tools/scripts/cold_start_artifact_quote_selftest.sh [--bench] [probe]
# Load only artifact helpers; never start a node, RPC, or live-datadir operation.
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
subject=${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}
fixture=$(mktemp -d /tmp/zcl-c3-artifact-quote.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
REPO_ROOT=$root
# Include the actual library import and any overriding probe helpers.
awk '/^# shellcheck source=tools\/scripts\/stopwatch_json_lib.sh/ {copy=1}
     copy {print} copy && /^write_artifact\(\)/ {artifact=1}
     artifact && /^}/ {exit}' "$subject" > "$fixture/helpers.sh"
grep -q '^write_artifact()' "$fixture/helpers.sh"
. "$fixture/helpers.sh"
declare -f json_string > "$fixture/formatter.sh"

date() { printf '2000000010\n'; }
ARTIFACT_ROOT=$fixture/artifacts ARTIFACT_DIR=$fixture/artifacts/run
start=2000000000 BUDGET=600 seeded=1 install_s=3 last_h=100 last_hdr=100 boots=2
PEER='fixture:39070' PEER_TIP=100 MODE=bundle DATADIR=''
BUNDLE_SNAP=$'fixture/\\"snapshot\t\r\n' BUNDLE_INDEX=fixture/index FILE_PEER=''
reason=$'quoted "reason"\\path\t\r\ntrailing\n\n'
# Preserve every byte of complete artifacts for every emitted verdict.
for verdict in pass skip fail seam; do
    case $verdict in pass) rc=0 ;; skip) rc=2 ;; fail) rc=1 ;; seam) rc=3 ;; esac
    . "$fixture/formatter.sh"
    write_artifact "$verdict" "$rc" "$reason" > /dev/null
    cp "$ARTIFACT_DIR/proof.json" "$fixture/actual.json"
    cp "$ARTIFACT_DIR/summary.txt" "$fixture/actual.txt"
    json_string() { printf '"%s"' "$(json_escape "$1")"; }
    write_artifact "$verdict" "$rc" "$reason" > /dev/null
    cmp "$fixture/actual.json" "$ARTIFACT_DIR/proof.json"
    cmp "$fixture/actual.txt" "$ARTIFACT_DIR/summary.txt"
done
. "$fixture/formatter.sh"
echo 'cold-start artifact quote: byte-identical artifacts for four verdicts PASS'

if (( bench )); then
    TIMEFORMAT='100 artifact writes: wall=%3R user=%3U sys=%3S seconds'
    for ((trial=0; trial<3; trial++)); do
        time for ((i=0; i<100; i++)); do
            write_artifact seam 3 "$reason" > /dev/null
        done
    done
fi

# A deterministic process-boundary check, independent of timing and load.
# The shared escaping helper must execute in the quoting caller's shell.
(
    caller=$BASHPID
    json_escape() { printf '%s\n' "$BASHPID" > "$fixture/escape.pid"; printf '%s' "$1"; }
    json_string probe > "$fixture/quoted"
    printf '"probe"' > "$fixture/expected"
    cmp "$fixture/expected" "$fixture/quoted"
    read -r escaped_in < "$fixture/escape.pid"
    if [[ $escaped_in != "$caller" ]]; then
        echo 'FAIL: probe quoting starts an extra shell per artifact string' >&2
        exit 1
    fi
)
echo 'cold-start artifact quote: zero nested quoting shells PASS'
