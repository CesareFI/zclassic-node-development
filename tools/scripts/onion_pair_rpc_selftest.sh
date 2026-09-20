#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Fixture-only bootstrap observer checks. No nodes, sockets or live datadirs.
# Usage: ZCL_JSONQ=/path/to/jsonq bash onion_pair_rpc_selftest.sh [--bench] [probe]
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
probe=${1:-$script_dir/onion_pair_watch.sh}
jsonq=${ZCL_JSONQ:-$script_dir/../../build/bin/jsonq}
[[ -x $jsonq ]] || { echo "onion RPC selftest: missing jsonq: $jsonq" >&2; exit 2; }
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-onion-rpc.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
awk '/^(log_has|observe_stages|descriptor_publication_observed)\(\) \{/ { copy=1 }
     copy { print }
     copy && /^}$/ { copy=0 }' "$probe" > "$fixture/predicates.sh"
. "$fixture/predicates.sh"
ISO_DD=$fixture/service ISO_PEER_DD=$fixture/client
mkdir -p "$ISO_DD" "$ISO_PEER_DD"
touch "$ISO_PEER_DD/.cookie"
export ONION_RPC_FIXTURE=$fixture ONION_RPC_JSONQ=$jsonq
cat > "$fixture/jsonq" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "$ONION_RPC_FIXTURE/queries"
exec "$ONION_RPC_JSONQ" "$@"
SH
chmod +x "$fixture/jsonq"
ZCL_JSONQ=$fixture/jsonq
iso_peer_rpc() {
    [[ $1 == onionstatus ]] || return 2
    printf 'call\n' >> "$fixture/rpcs"
    printf '%s' "$response"
}
reset_flags() {
    DIAL_ATTEMPTED=false INTRODUCE1_SEEN=false RENDEZVOUS1_SEEN=false
    RENDEZVOUS_SEEN=false CIRCUIT_READY=false DESCRIPTOR_UPLOADED=false
    CLIENT_TOR_READY=false P2P_FRAMING_SEEN=false
}
observe() { observe_stages || true; }
check() {
    local label=$1
    shift
    if ! "$@"; then echo "onion RPC selftest: FAIL $label" >&2; exit 1; fi
}
complete='{"result":{"tor_ready":true,"outbound_streams":{"dial_started":1,"circuit_ready":1,"bytes_to_peer":4,"bytes_from_peer":0}}}'
reset_flags
response=$complete
rm "$ISO_PEER_DD/.cookie"
observe
check no-cookie-no-rpc test ! -e "$fixture/rpcs"
touch "$ISO_PEER_DD/.cookie"

# Missing, malformed and zero observations cannot complete the milestones.
for response in '' '{}' '{"result":' \
    '{"result":{"tor_ready":false,"outbound_streams":{"dial_started":0,"circuit_ready":0,"bytes_to_peer":0,"bytes_from_peer":0}}}'; do
    observe
    check absent-stays-unseen test "$CLIENT_TOR_READY:$DIAL_ATTEMPTED:$CIRCUIT_READY:$P2P_FRAMING_SEEN" = false:false:false:false
done

# Each RPC-derived milestone alone must keep observation active. This also
# proves that seeing every log milestone does not suppress the needed RPC.
for flag in CLIENT_TOR_READY DIAL_ATTEMPTED CIRCUIT_READY P2P_FRAMING_SEEN; do
    CLIENT_TOR_READY=true DIAL_ATTEMPTED=true CIRCUIT_READY=true P2P_FRAMING_SEEN=true
    INTRODUCE1_SEEN=true RENDEZVOUS1_SEEN=true DESCRIPTOR_UPLOADED=true
    printf -v "$flag" false
    : > "$fixture/rpcs"
    response=$complete
    observe
    check "recover-$flag" test "${!flag}" = true
    check "poll-missing-$flag" test -s "$fixture/rpcs"
done

# Byte evidence still requires both counters to parse and at least one to
# advance. Invalid evidence retries; a later valid response completes it.
P2P_FRAMING_SEEN=false
response='{"result":{"outbound_streams":{"bytes_to_peer":4}}}'
observe
check missing-byte-counter test "$P2P_FRAMING_SEEN" = false
response='{"result":{"outbound_streams":{"bytes_to_peer":0,"bytes_from_peer":7}}}'
observe
check incoming-byte-evidence test "$P2P_FRAMING_SEEN" = true

# Completing the RPC milestones must not stop missing service/log milestones.
INTRODUCE1_SEEN=false RENDEZVOUS1_SEEN=false RENDEZVOUS_SEEN=false DESCRIPTOR_UPLOADED=false
printf 'INTRODUCE1 sent\n' > "$ISO_PEER_DD/tor.log"
printf 'RENDEZVOUS1 sent\nHS_DESC UPLOADED\n' > "$ISO_DD/tor.log"
: > "$fixture/rpcs"
: > "$fixture/queries"
response='{}'
observe
check delayed-logs test "$INTRODUCE1_SEEN:$RENDEZVOUS1_SEEN:$RENDEZVOUS_SEEN:$DESCRIPTOR_UPLOADED" = true:true:true:true
check latched-rpc-flags test "$CLIENT_TOR_READY:$DIAL_ATTEMPTED:$CIRCUIT_READY:$P2P_FRAMING_SEEN" = true:true:true:true
rpc_calls=$(wc -l < "$fixture/rpcs")
query_calls=$(wc -l < "$fixture/queries")
printf 'completed RPC milestones: onionstatus calls=%s JSON readers=%s\n' "$rpc_calls" "$query_calls"
if [[ $bench == 1 ]]; then
    response=$complete
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    echo 'benchmark: 100 completed-milestone polls; local fixture RPC and real jsonq'
    time for ((i=0; i<100; i++)); do observe; done
fi
check completed-rpc-budget test "$rpc_calls" -eq 0
check completed-query-budget test "$query_calls" -eq 0
echo 'onion RPC selftest: PASS'
