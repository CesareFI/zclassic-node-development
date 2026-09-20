#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise polling cancellation with local clients; no node or sockets.
set -euo pipefail
self_dir=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
subject=${1:-$self_dir/two_node_peer_tip.sh}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/z23-peer-poll-deadline.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
export fixture
cat > "$fixture/rpc" <<'RPC'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$fixture/calls"
if [[ $fixture_mode == hash && $1 == getblockcount ]]; then
    printf '101\n' > "$fixture/clock"
    printf '{"result":15,"error":null}\n'
    exit 0
fi
[[ $fixture_mode == success ]] || printf '102\n' > "$fixture/clock"
# Plausible partial output must not survive timeout or a nonzero exit.
if [[ $1 == getblockhash ]]; then
    printf '{"result":"%064d","error":null}\n' 0
else
    printf '{"result":15,"error":null}\n'
fi
[[ $fixture_mode != success ]] || exit 0
[[ $fixture_mode != failed ]] || exit 7
[[ $fixture_mode != ignores-term ]] || trap '' TERM
exec sleep 8
RPC
chmod 700 "$fixture/rpc"
touch "$fixture/.cookie"
cat > "$fixture/run" <<'RUN'
#!/usr/bin/env bash
set -euo pipefail
source "$1"
RPC_BIN="$fixture/rpc"
date() { cat "$fixture/clock"; }
timeout() {
    printf '%s %s\n' "$1" "$2" >> "$fixture/allowances"
    command timeout "$@"
}
case $fixture_poll in
    readiness) tn_wait_rpc "$fixture" 39071 '' 102 ;;
    height) tn_wait_height "$fixture" 39071 '' 15 102 "$(printf '%064d' 0)" ;;
esac
RUN
failures=0
for scenario in readiness:stalled height:stalled height:hash readiness:ignores-term readiness:failed readiness:success height:success; do
    export fixture_poll=${scenario%%:*} fixture_mode=${scenario#*:}
    printf '100\n' > "$fixture/clock"
    : > "$fixture/calls"
    : > "$fixture/allowances"
    began=$SECONDS
    rc=0
    timeout --kill-after=1 5 bash "$fixture/run" "$subject" > "$fixture/output" 2>&1 || rc=$?
    printf 'peer-poll deadline: %s rc=%s elapsed=%ss\n' "$scenario" "$rc" "$((SECONDS - began))"
    # The deterministic clock grades the deadline. The outer watchdog is
    # only containment for regressions; a watchdog timeout is never a pass.
    expected_rc=1
    [[ $fixture_mode != success ]] || expected_rc=0
    if [[ $rc != "$expected_rc" ]]; then
        cat "$fixture/output" >&2
        failures=$((failures + 1))
    fi
    expected='--kill-after=1 2'
    [[ $fixture_mode != hash ]] || expected+=$'\n--kill-after=1 1'
    [[ $scenario != height:success ]] || expected+=$'\n--kill-after=1 2'
    if [[ $(cat "$fixture/allowances") != "$expected" ]]; then
        printf 'peer-poll deadline: wrong RPC allowances for %s\n' "$scenario" >&2
        failures=$((failures + 1))
    fi
done
# A height that consumes the final second must not dispatch its hash query.
# Exercise the real tn_result guard rather than a replacement polling helper.
(
    source "$subject"
    RPC_BIN="$fixture/rpc"
    date() { printf '102\n'; }
    TN_RPC_DEADLINE=102
    : > "$fixture/calls"
    if tn_blockhash "$fixture" 39071 15; then exit 1; fi
    [[ ! -s $fixture/calls ]]
) || { printf 'peer-poll deadline: expired read dispatched\n' >&2; failures=$((failures + 1)); }
[[ $failures == 0 ]] || { printf 'peer-poll deadline: FAIL (%s cases)\n' "$failures" >&2; exit 1; }
printf 'peer-poll deadline: PASS\n'
