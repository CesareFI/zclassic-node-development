#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the real sampler against stalled local RPC clients; no node or peer.
# Usage: sh tools/scripts/fold_profile_rpc_deadline_selftest.sh [fold_profile.sh]
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
subject=${1:-$script_dir/fold_profile.sh}
fixture=$(mktemp -d /tmp/zcl-fold-rpc-deadline.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if command -v timeout >/dev/null 2>&1; then
    RPC_TIMEOUT_CMD=timeout
elif command -v gtimeout >/dev/null 2>&1; then
    RPC_TIMEOUT_CMD=gtimeout
else
    echo 'fold-profile deadline selftest: timeout or gtimeout required' >&2
    exit 1
fi
export RPC_TIMEOUT_CMD fixture
sed -n '/^# .*sampling primitives/,/^# .*launch the copy/{ /^# .*launch the copy/d; p; }' \
    "$subject" > "$fixture/sampling.sh"
cat > "$fixture/mock-node" <<'SH'
#!/bin/sh
set -eu
[ "$1" = "-datadir=$fixture/copy with spaces" ] && [ "$2" = '-rpcport=18299' ] || exit 90
shift 2
case "$*" in
    'ops state --subsystem=reducer_drive') endpoint=drive ;;
    'ops state --subsystem=reducer_frontier') endpoint=frontier ;;
    'ops state --subsystem=reducer_stage_profile --key=proof_validate') endpoint=proof_validate ;;
    'ops state --subsystem=reducer_stage_profile --key=tip_finalize') endpoint=tip_finalize ;;
    'ops state --subsystem=reducer_stage_profile --key=utxo_apply') endpoint=utxo_apply ;;
    *) exit 91 ;;
esac
printf '%s\n' "$endpoint" >> "$fixture/calls"
# A plausible prefix from a timed-out client is not a usable observation.
printf '{"provable_tip":123,"drain_rounds_total":4,"blocks":5,"total_us":6}\n'
if [ "$endpoint" = "$fault" ]; then
    if [ "$mode" = resistant ]; then trap '' TERM; fi
    exec sleep 30
fi
SH
chmod +x "$fixture/mock-node"
cat > "$fixture/run.sh" <<'SH'
set -eu
. "$fixture/sampling.sh"
NODE_BIN=$fixture/mock-node COPY="$fixture/copy with spaces" PORT=18299
CSV=$fixture/samples.csv
write_header
# Seed one good observation, then require the stalled read to preserve it.
saved_fault=$fault
fault=none
sample_once
cp "$CSV" "$fixture/healthy.csv"
: > "$fixture/calls"
fault=$saved_fault
if sample_once; then
    echo 'FAIL: stalled RPC became a successful sample' >&2
    exit 1
fi
cmp "$CSV" "$fixture/healthy.csv"
[ "$(wc -l < "$fixture/calls")" -eq "$expected_calls" ]
fault=none
: > "$fixture/calls"
sample_once
[ "$(wc -l < "$fixture/calls")" -eq 5 ]
awk -F, 'NF != 50 {exit 1} END {if (NR != 3) exit 1}' "$CSV"
SH
expected_calls=0 mode=cooperative
export expected_calls mode fault
for fault in drive frontier proof_validate tip_finalize utxo_apply drive; do
    if [ "$expected_calls" -eq 5 ]; then
        expected_calls=1 mode=resistant
    else
        expected_calls=$((expected_calls + 1))
    fi
    start=$(date +%s)
    rc=0
    "$RPC_TIMEOUT_CMD" -k 1 8 sh "$fixture/run.sh" > "$fixture/out" 2> "$fixture/err" || rc=$?
    elapsed=$(($(date +%s) - start))
    if [ "$rc" -ne 0 ]; then
        printf 'FAIL: %s/%s rc=%s elapsed=%ss (outer guard is 8s)\n' "$fault" "$mode" "$rc" "$elapsed" >&2
        cat "$fixture/err" >&2
        exit 1
    fi
    grep -q "sample rejected:.* RPC failed or empty" "$fixture/err"
    printf 'PASS: %s/%s rejected in %ss; CSV retained, later RPCs skipped, recovery passed\n' \
        "$fault" "$mode" "$elapsed"
done
