#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Fixture-only bootstrap milestone checks and optional log scan benchmark.
# Usage: bash onion_pair_log_selftest.sh [--bench] [onion_pair_watch.sh]
set -euo pipefail
export LC_ALL=C
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
probe="${1:-$script_dir/onion_pair_watch.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-onion-log.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

# Load only the actual observers; never enter the live probe or spawn nodes.
# These functions have a top-level closing brace.
awk '/^(log_has|observe_stages|descriptor_publication_observed)\(\) \{/ { copy=1 }
     copy { print }
     copy && /^}$/ { copy=0 }' "$probe" > "$fixture/predicates.sh"
. "$fixture/predicates.sh"
ISO_DD="$fixture/service"
mkdir -p "$ISO_DD"
checks=0
expect() {
    local expected=$1 label=$2 actual=0
    shift 2
    "$@" || actual=$?
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL %s: expected status %s, got %s\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
    checks=$((checks + 1))
}

expect 1 missing log_has "$fixture/missing" 'INTRODUCE1 sent'
expect 1 directory log_has "$fixture" 'INTRODUCE1 sent'
: > "$ISO_DD/tor.log"
expect 1 empty log_has "$ISO_DD/tor.log" 'INTRODUCE1 sent'
printf 'intent only\nINTRODUCE1 sent\nmore traffic\n' > "$ISO_DD/tor.log"
expect 0 multiline log_has "$ISO_DD/tor.log" 'INTRODUCE1 sent'
expect 1 absent log_has "$ISO_DD/tor.log" 'RENDEZVOUS1 sent'
printf 'noise\000INTRODUCE1 sent\000tail' > "$ISO_DD/tor.log"
expect 0 binary log_has "$ISO_DD/tor.log" 'INTRODUCE1 sent'
printf 'onion circuit established' > "$ISO_DD/tor.log"
expect 0 unterminated log_has "$ISO_DD/tor.log" 'onion stage=circuit_ready|onion circuit established'
expect 1 invalid-regex log_has "$ISO_DD/tor.log" '['
for marker in 'waiting for DESCRIPTOR PUBLICATION' 'Dynhost service successfully activated' \
              'hs_service_callback' 'Uploaded hidden service descriptor (status 500'; do
    printf '%s\n' "$marker" > "$ISO_DD/tor.log"
    expect 1 intent-is-not-upload descriptor_publication_observed
done
for marker in 'Hidden service descriptor upload complete' \
              'Uploaded hidden service descriptor (status 200' \
              'Uploading hidden service descriptor: finished with status 200' \
              'HS_DESC UPLOADED'; do
    printf '%s\n' "$marker" > "$ISO_DD/tor.log"
    expect 0 tor-upload descriptor_publication_observed
done
printf 'no upload here\n' > "$ISO_DD/tor.log"
printf 'DESCRIPTOR PUBLICATION observed\n' > "$ISO_DD/node.log"
expect 0 node-upload-fallback descriptor_publication_observed
printf 'waiting for DESCRIPTOR PUBLICATION\n' > "$ISO_DD/node.log"
expect 1 node-intent-refused descriptor_publication_observed

ISO_PEER_DD="$fixture/client"
mkdir -p "$ISO_PEER_DD"
grep_calls=0
grep() { grep_calls=$((grep_calls + 1)); command grep "$@"; }
DIAL_ATTEMPTED=false INTRODUCE1_SEEN=false RENDEZVOUS1_SEEN=false
RENDEZVOUS_SEEN=false CIRCUIT_READY=false DESCRIPTOR_UPLOADED=false
CLIENT_TOR_READY=false P2P_FRAMING_SEEN=false
# Match the live cleanup caller; missing observations are checked through
# the milestone flags below.
observe_stages || true
expect 0 missing-stays-unseen test "$DESCRIPTOR_UPLOADED:$CIRCUIT_READY" = false:false
printf 'Connecting to onion addnode\n' > "$ISO_PEER_DD/node.log"
observe_stages || true
expect 0 partial-milestones test "$DIAL_ATTEMPTED:$INTRODUCE1_SEEN:$CIRCUIT_READY" = true:false:false
printf 'RENDEZVOUS2 received\n' > "$ISO_PEER_DD/tor.log"
observe_stages || true
expect 0 circuit-tor-fallback test "$CIRCUIT_READY:$INTRODUCE1_SEEN" = true:false
# Exercise the node-log alternative separately as well.
CIRCUIT_READY=false
printf 'onion stage=circuit_ready\n' >> "$ISO_PEER_DD/node.log"
printf 'INTRODUCE1 sent\n' > "$ISO_PEER_DD/tor.log"
printf 'RENDEZVOUS1 sent\nHS_DESC UPLOADED\n' > "$ISO_DD/tor.log"
observe_stages || true
expect 0 late-milestones test "$DIAL_ATTEMPTED:$INTRODUCE1_SEEN:$RENDEZVOUS1_SEEN:$RENDEZVOUS_SEEN:$CIRCUIT_READY:$DESCRIPTOR_UPLOADED" = true:true:true:true:true:true
grep_calls=0
observe_stages || true
repeat_reads=$grep_calls
# Log rotation must not erase an already observed event. RPC observations
# still run, even after every log milestone is latched.
: > "$ISO_PEER_DD/node.log"
: > "$ISO_PEER_DD/tor.log"
: > "$ISO_DD/tor.log"
: > "$ISO_DD/node.log"
touch "$ISO_PEER_DD/.cookie"
iso_peer_rpc() { printf 'called\n' >> "$fixture/rpc-calls"; printf '{}'; }
ZCL_JSONQ="$fixture/jsonq"
cat > "$ZCL_JSONQ" <<'EOF'
#!/usr/bin/env bash
case "$2" in
    result.tor_ready) printf true ;;
    result.outbound_streams.bytes_to_peer) printf 42 ;;
    *) printf 0 ;;
esac
EOF
chmod +x "$ZCL_JSONQ"
observe_stages || true
expect 0 rpc-still-observed test -s "$fixture/rpc-calls"
expect 0 rpc-milestones test "$CLIENT_TOR_READY:$P2P_FRAMING_SEEN" = true:true
expect 0 latched-after-rotation test "$DIAL_ATTEMPTED:$INTRODUCE1_SEEN:$RENDEZVOUS1_SEEN:$CIRCUIT_READY:$DESCRIPTOR_UPLOADED" = true:true:true:true:true
rm "$ISO_PEER_DD/.cookie"

if [ "$bench" = 1 ]; then
    # A completed bootstrap marker can precede a growing traffic log. Use
    # real non-NUL lines so grep cannot skip sparse extents or binary data.
    printf 'INTRODUCE1 sent\n' > "$fixture/large.log"
    awk 'BEGIN { line=sprintf("%0127d", 0); for (i=0; i<1048576; i++) print line }' \
        >> "$fixture/large.log"
    expect 0 early-large log_has "$fixture/large.log" 'INTRODUCE1 sent'
    printf 'RENDEZVOUS1 sent\n' >> "$fixture/large.log"
    expect 0 late-large log_has "$fixture/large.log" 'RENDEZVOUS1 sent'
    expect 1 missing-large log_has "$fixture/large.log" 'HS_DESC UPLOADED'
    # Keep the completed markers in every log; the flags were observed above.
    for log in "$ISO_DD/node.log" "$ISO_DD/tor.log" "$ISO_PEER_DD/node.log" "$ISO_PEER_DD/tor.log"; do
        cp "$fixture/large.log" "$log"
        printf 'Connecting to onion addnode\nonion stage=circuit_ready\nHS_DESC UPLOADED\n' >> "$log"
    done
    printf 'benchmark: 100 completed-stage observations, bytes per log=%s, warm file cache\n' \
        "$(wc -c < "$fixture/large.log")"
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time for ((i=0; i<100; i++)); do
        observe_stages || true
    done
fi
printf 'completed-stage log searches per observation=%s\n' "$repeat_reads"
expect 0 completed-stages-do-not-rescan test "$repeat_reads" = 0
printf 'onion log selftest: PASS (%s cases)\n' "$checks"
