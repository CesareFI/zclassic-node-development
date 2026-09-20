#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the repeat-run driver with a mock stopwatch and RPC executable.
# Usage: bash tools/scripts/c3_stopwatch_scratch_selftest.sh [driver]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
subject=${1:-$root/tools/scripts/c3_stopwatch_triple_run.sh}
work=$(mktemp -d "${TMPDIR:-/tmp}/z23-triple-scratch.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/repo/tools/scripts" "$work/bin" "$work/home"
cp "$subject" "$work/repo/tools/scripts/c3_stopwatch_triple_run.sh"
cat > "$work/bin/node" <<'NODE'
#!/usr/bin/env bash
set -eu
if [[ ${1:-} == --version ]]; then echo fixture; exit; fi
dd=${1#-datadir=}
if [[ $dd != fixture-peer ]]; then
    printf '%s\n' "$dd" >> "$FIXTURE_CALLS"
    [[ -f $dd/.cookie ]] || exit 1
fi
printf '{"ok":true,"data":{"height":100,"hash":"%064d"}}\n' 1
NODE
cat > "$work/repo/tools/scripts/cold_start_to_tip_stopwatch.sh" <<'HARNESS'
#!/usr/bin/env bash
set -eu
scratch=${ZCL_CS_ROOT:-$HOME/.local/state/zclassic23/scratch/coldstart}
dd=$(mktemp -d "$scratch/zcl-c3-stopwatch.XXXXXX")
trap 'rm -rf -- "$dd" "$dd-home"' EXIT
mkdir "$dd-home"
if [[ ${FIXTURE_RETAIN:-0} == 1 ]]; then : > "$scratch/retained-fixture"; fi
printf '%s\n' "$dd" >> "$FIXTURE_EXPECTED"
run=$(wc -l < "$FIXTURE_EXPECTED")
if [[ ${FIXTURE_READY:-1} == 1 ]]; then : > "$dd/.cookie"; fi
artifact="$FIXTURE_ARTIFACTS/$ZCL_CS_RUN_ID"
mkdir -p "$artifact"
printf '{"wall_clock_seconds":1,"boots":1,"final_hstar":100,"final_network_tip":100}\n' > "$artifact/proof.json"
printf 'unix_s\tblockers\n1\t-\n' > "$artifact/samples.tsv"
echo "cold-start-wipe-stopwatch: artifact=$artifact"
# Wait for the observer, with a bounded one-second no-observation witness.
for ((i=0;i<100;i++)); do
    if [[ ${FIXTURE_READY:-1} == 1 ]] &&
        grep -q $'\t100\t' "$FIXTURE_OUT/run$run.client-tip.tsv"; then break; fi
    /bin/sleep 0.01
done
exit "${FIXTURE_EXIT:-0}"
HARNESS
cat > "$work/bin/sleep" <<'SLEEP'
#!/bin/sh
# Accelerate only the driver's polling cadence, not its decisions.
exec /bin/sleep 0.01
SLEEP
chmod +x "$work/bin/node" "$work/bin/sleep"
export PATH="$work/bin:$PATH"
export HOME="$work/home"
export FIXTURE_CALLS="$work/calls" FIXTURE_EXPECTED="$work/expected"
export FIXTURE_ARTIFACTS="$work/artifacts"
export FIXTURE_READY=1 FIXTURE_EXIT=0 FIXTURE_RETAIN=0
driver="$work/repo/tools/scripts/c3_stopwatch_triple_run.sh"
run_case() {
    local name=$1 want=$2 rc=0 expected_count observed_count dd
    export FIXTURE_OUT="$work/$name"
    : > "$FIXTURE_CALLS"; : > "$FIXTURE_EXPECTED"
    bash "$driver" --peer=fixture:1 --peer-datadir=fixture-peer \
        --bin="$work/bin/node" --runs=2 --out="$work/$name" \
        > "$work/$name.log" 2>&1 || rc=$?
    expected_count=$(wc -l < "$FIXTURE_EXPECTED")
    observed_count=$(sort -u "$FIXTURE_CALLS" | wc -l)
    printf '%s: runs=%s observed_clients=%s exit=%s\n' "$name" "$expected_count" "$observed_count" "$rc"
    if [[ $rc != "$want" ]]; then cat "$work/$name.log" >&2; exit 1; fi
    if [[ $want == 2 ]]; then
        [[ $expected_count == 0 && $observed_count == 0 ]]
        return
    fi
    if [[ ${FIXTURE_READY:-1} == 1 ]]; then
        sort -u "$FIXTURE_EXPECTED" > "$work/expected.sorted"
        sort -u "$FIXTURE_CALLS" > "$work/calls.sorted"
        cmp "$work/expected.sorted" "$work/calls.sorted"
        [[ $expected_count == 2 && $observed_count == 2 ]]
    else
        [[ $observed_count == 0 ]]
    fi
    while IFS= read -r dd; do
        [[ ! -e $dd && ! -e $dd-home ]]
        if [[ ${FIXTURE_RETAIN:-0} == 1 ]]; then
            [[ -f ${dd%/*}/retained-fixture ]]
        else
            [[ ! -e ${dd%/*} ]]
        fi
    done < "$FIXTURE_EXPECTED"
    if [[ ${FIXTURE_RETAIN:-0} == 1 ]]; then
        [[ $(grep -c 'scratch retained:' "$work/$name.log") == 2 ]]
    fi
}
unset ZCL_CS_ROOT ZCL_CS_FILE_PEER ZCL_CS_NODE_BIN ZCL_CS_PEER_RPCPORT
mkdir -p "$HOME/.local/state/zclassic23/scratch/coldstart"
run_case default 0
export ZCL_CS_ROOT="$work/custom scratch [root]"
mkdir -p "$ZCL_CS_ROOT/zcl-c3-stopwatch.unrelated"
: > "$ZCL_CS_ROOT/zcl-c3-stopwatch.unrelated/.cookie"
run_case custom 0
export FIXTURE_READY=0
run_case unready 1
export FIXTURE_READY=1 FIXTURE_EXIT=3
run_case seam 1
export FIXTURE_RETAIN=1
run_case residue 1
[[ -f $ZCL_CS_ROOT/zcl-c3-stopwatch.unrelated/.cookie ]]
export ZCL_CS_ROOT="$work/missing-parent"
run_case absent 2
printf 'C3 repeat-run scratch isolation: PASS\n'
