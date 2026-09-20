#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise only reference-tip capture; never launch a node or contact a peer.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_file="${1:-$root/tools/scripts/cold_start_to_tip_probe.sh}"
fixture="$(mktemp -d /tmp/z23-peer-tip-budget.XXXXXX)"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
awk '/^# Reference peer tip / {copy=1; next}
     copy && /^DATADIR=/ {exit} copy {print}' "$source_file" > "$fixture/capture.sh"
[[ -s "$fixture/capture.sh" ]] || { echo 'FAIL: tip capture absent' >&2; exit 1; }
cat > "$fixture/rpc" <<'RPC'
#!/usr/bin/env bash
[[ "$#" == 1 && "$1" == getblockcount ]] || exit 99
[[ "$ZCL_DATADIR" == "$TEST_TIP_DATADIR" && "$ZCL_RPCPORT" == 39099 ]] || exit 98
case "$TEST_REPLY" in
    hang) exec sleep 30 ;;
    ignore-term) trap '' TERM; exec sleep 30 ;;
    *) printf '%s\n' "$TEST_REPLY" ;;
esac
exit "$TEST_STATUS"
RPC
chmod +x "$fixture/rpc"
cat > "$fixture/run" <<'RUN'
#!/usr/bin/env bash
set -uo pipefail
TIP_DATADIR="$TEST_TIP_DATADIR" PEER_RPC=39099 RPC_BIN="$TEST_RPC"
skip() { printf 'skip: %s\n' "$*" >&2; exit 2; }
. "$TEST_CAPTURE"
printf '%s\n' "$PEER_TIP"
RUN
export TEST_TIP_DATADIR="$fixture/unused datadir" TEST_RPC="$fixture/rpc"
export TEST_CAPTURE="$fixture/capture.sh"
failures=0
check() {
    local label="$1" expected_rc="$4" expected_tip="$5" rc=0 actual
    actual=$(TEST_REPLY="$2" TEST_STATUS="$3" timeout --kill-after=1 8 \
        bash "$fixture/run" 2> "$fixture/stderr") || rc=$?
    if [[ "$rc" != "$expected_rc" || "$actual" != "$expected_tip" ]]; then
        printf 'FAIL: %s rc=%s tip=<%s>, expected %s/<%s>\n' \
            "$label" "$rc" "$actual" "$expected_rc" "$expected_tip" >&2
        failures=$((failures + 1))
    elif [[ "$expected_rc" == 2 ]] && [[ ! -s "$fixture/stderr" ]]; then
        printf 'FAIL: %s missing refusal reason\n' "$label" >&2
        failures=$((failures + 1))
    else
        printf 'PASS: %s\n' "$label"
    fi
}
check valid '{"result":3200000}' 0 0 3200000
check failed-with-tip '{"result":3200000}' 1 2 ''
check empty '' 0 2 ''
check malformed '{"error":"unavailable"}' 0 2 ''
check low '{"result":1000000}' 0 2 ''
check negative '{"result":-1}' 0 2 ''
check stalled hang 0 2 ''
check ignores-term ignore-term 0 2 ''
[[ "$failures" == 0 ]] || exit 1
echo 'cold-start peer tip: PASS (bounded reference capture, no node/network)'
