#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the real recovery harness with a deterministic clock and RPC fixture.
# Only the disposable /tmp upstream below receives signals; no node or network.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
harness="${1:-$repo_root/tools/scripts/network_disruption_recovery_stopwatch.sh}"
if [ ! -r /proc/self/cmdline ]; then
    echo 'netdisrupt-timing-selftest: SKIP (harness requires Linux /proc)' >&2
    exit 2
fi
fixture="$(mktemp -d /tmp/zcl-netdisrupt-timing.XXXXXX)"
upstream_pid=''
cleanup() {
    if [ -n "$upstream_pid" ]; then
        kill -CONT "$upstream_pid" 2>/dev/null || true
        kill "$upstream_pid" 2>/dev/null || true
        wait "$upstream_pid" 2>/dev/null || true
    fi
    rm -rf -- "$fixture"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$fixture/bin" "$fixture/client" "$fixture/upstream"
mkfifo "$fixture/wait"
# Bash blocks on its own FIFO without spawning a child that could be orphaned.
bash -c 'read -r -t 60 line <>"$1" || :' fixture-upstream \
    "$fixture/wait" "-datadir=$fixture/upstream" &
upstream_pid=$!
printf '%s\n' "$upstream_pid" > "$fixture/upstream.pid"

cat > "$fixture/bin/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == '+%s' ]] || { echo 'unexpected fixture date request' >&2; exit 1; }
root="${BASH_SOURCE[0]%/*}/.."
read -r now < "$root/clock"
printf '%s\n' "$now"
# Model processing time after the terminal sample, before artifact emission.
read -r mode < "$root/mode"
read -r count < "$root/count"
if [ "$mode" = artifact_delay ] && [ "$count" = 2 ] &&
   [ ! -e "$root/delayed" ]; then
    printf '%s\n' "$((now + 3))" > "$root/clock"
    : > "$root/delayed"
fi
EOF
cat > "$fixture/bin/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
clock="${BASH_SOURCE[0]%/*}/../clock"
read -r now < "$clock"
printf '%s\n' "$((now + $1))" > "$clock"
EOF
cat > "$fixture/bin/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="${BASH_SOURCE[0]%/*}/.."
case "$*" in
    *'dumpstate reducer_frontier')
        read -r count < "$root/count"
        count=$((count + 1))
        printf '%s\n' "$count" > "$root/count"
        read -r mode < "$root/mode"
        hs=100; tip=103
        if [ "$count" = 1 ]; then
            tip=100
        elif [ "$mode" = artifact_delay ]; then
            hs=103
        elif [ "$count" -gt 2 ]; then
            case "$mode" in
                on_time) hs=$((count == 3 ? 101 : 103)) ;;
                late_poll) hs=103 ;;
                late_rpc)
                    read -r now < "$root/clock"
                    printf '%s\n' "$((now + 2))" > "$root/clock"
                    hs=103 ;;
                progress) hs=$((98 + count)) ;;
                stalled) hs=100 ;;
                *) echo "unknown fixture mode: $mode" >&2; exit 1 ;;
            esac
        fi
        printf '{"hstar":%s,"network_tip":%s,"network_tip_read_ok":true}\n' "$hs" "$tip"
        ;;
    *'dumpstate blocker') printf '{"active_count":0}\n' ;;
    *'ops logs'*) printf 'fixture diagnostic log\n' ;;
    *) echo "unexpected fixture RPC: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$fixture/bin/"*

failed=0
run_case() {
    local mode="$1" sample="$2" expected_rc="$3" seconds="$4" verdict="$5" rc=0 proof
    printf '1000\n' > "$fixture/clock"
    printf '0\n' > "$fixture/count"
    printf '%s\n' "$mode" > "$fixture/mode"
    PATH="$fixture/bin:$PATH" ZCL_ND_RUN_ID="$mode" \
        ZCL_ND_ARTIFACT_ROOT="$fixture/artifacts" \
        bash "$harness" --bin="$fixture/bin/node" \
        --upstream-pid-file="$fixture/upstream.pid" --client-rpc=1 \
        --client-datadir="$fixture/client" --cut-secs=600 --budget=2 \
        --sample="$sample" > "$fixture/$mode.log" 2>&1 || rc=$?
    proof="$fixture/artifacts/$mode/proof.json"
    if [ "$rc" != "$expected_rc" ] ||
       ! grep -qF "\"wall_clock_seconds\": $seconds," "$proof" ||
       ! grep -qF "\"verdict\": \"$verdict\"," "$proof" ||
       ! grep -qF '"cut_seconds": 600,' "$proof" ||
       ! grep -qFx "WALL_CLOCK_SECONDS=$seconds" "$fixture/$mode.log" ||
       ! kill -0 "$upstream_pid" 2>/dev/null ||
       grep -qE '^State:.*T' "/proc/$upstream_pid/status"; then
        echo "FAIL: $mode (rc=$rc expected=$expected_rc, recovery=${seconds}s)" >&2
        cat "$fixture/$mode.log" >&2
        failed=1
    else
        echo "ok: $mode (600s outage, recovery=${seconds}s, verdict=$verdict)"
    fi
}
run_case on_time 1 0 2 pass
run_case late_poll 3 3 3 seam
run_case late_rpc 1 3 3 seam
run_case progress 1 3 2 seam
run_case stalled 1 1 2 fail
run_case artifact_delay 1 0 0 pass
if [ "$failed" != 0 ]; then
    echo 'netdisrupt-timing-selftest: FAIL' >&2
    exit 1
fi
echo 'netdisrupt-timing-selftest: PASS'
