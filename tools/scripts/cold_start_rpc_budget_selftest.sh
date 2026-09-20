#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Bound the real time-to-tip observer with local RPC doubles, without a node.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}
fixture=$(mktemp -d /tmp/z23-c3-rpc-budget.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
sed -n '/^read_tip_sample() {/,/^}/p' "$subject" > "$fixture/observer.sh"
grep -q '^read_tip_sample() {' "$fixture/observer.sh"
. "$fixture/observer.sh"
cat > "$fixture/rpc" <<'SH'
#!/usr/bin/env bash
set -eu
[[ $* == getblockchaininfo && $ZCL_RPCPORT == 39071 ]] || exit 9
printf 'called\n' >> "$ZCL_DATADIR/calls"
case $RPC_FIXTURE_MODE in
    stalled) sleep 4 ;;
    ignores-term) trap '' TERM; sleep 4 ;;
    failed) printf '{"blocks":3200000,"headers":3200000}\n'; exit 7 ;;
esac
printf '{"blocks":3200000,"headers":3200000}\n'
SH
chmod +x "$fixture/rpc"
DATADIR=$fixture RPC=39071 RPC_BIN=$fixture/rpc
export RPC_FIXTURE_MODE
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Freeze the stopwatch clock, but run the real timeout and child processes.
# Assertions grade cancellation and the requested allowance, never host speed.
date() { cat "$fixture/clock"; }
timeout() {
    local status=0
    printf '%s\n' "$@" > "$fixture/timeout-args"
    command timeout "$@" || status=$?
    printf '102\n' > "$fixture/clock"
    return "$status"
}
for RPC_FIXTURE_MODE in stalled ignores-term; do
    printf '100\n' > "$fixture/clock"
    BUDGET=10 start=92 bci=stale
    began=$SECONDS
    rc=0
    read_tip_sample || rc=$?
    duration=$((SECONDS - began))
    printf 'mode=%s remaining=2 wall_seconds=%s rc=%s retained_bytes=%s\n' \
        "$RPC_FIXTURE_MODE" "$duration" "$rc" "${#bci}"
    if [[ $baseline == 0 ]]; then
        [[ $rc != 0 && -z $bci ]] || fail 'late RPC output retained'
        mapfile -t args < "$fixture/timeout-args"
        [[ ${args[0]} == --kill-after=1 && ${args[1]} == 2 ]] ||
            fail 'RPC did not use remaining budget plus bounded kill grace'
    fi
done
[[ $baseline == 0 ]] || exit 0

# A consumed budget must not launch any observer or retain an older sample.
: > "$fixture/calls"
RPC_FIXTURE_MODE=success BUDGET=2 start=100 bci=stale
if read_tip_sample; then fail 'expired budget accepted'; fi
[[ ! -s $fixture/calls && -z $bci ]] || fail 'expired budget dispatched RPC'

# Success and command failure retain their original observation semantics.
BUDGET=30 start=102
read_tip_sample || fail 'timely successful observation refused'
[[ $bci == '{"blocks":3200000,"headers":3200000}' ]] || fail 'reply changed'
RPC_FIXTURE_MODE=failed bci=stale
read_tip_sample || fail 'timely RPC failure stopped further polling'
[[ -z $bci ]] || fail 'failed RPC output retained'
echo 'cold-start RPC budget: PASS (stall, forced termination, expired, success, failure)'
