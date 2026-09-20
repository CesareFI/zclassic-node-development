#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic join-observer regression; no node, sockets or messages.
# Usage: bash tools/scripts/ux_join_peer_scan_selftest.sh [--bench] [SOURCE]
set -euo pipefail
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
script_dir=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
subject=${1:-$script_dir/ux_join_drill.sh}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/z23-join-peer-scan.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
export fixture
export JOIN_TEST_JSONQ=${ZCL_JSONQ:-$script_dir/../../build/bin/jsonq}
[[ -x $JOIN_TEST_JSONQ ]] || { echo 'join-peer-scan: build jsonq first' >&2; exit 2; }

# Exercise the actual PEERED loop, stopping before its live failure handler.
awk '
    /^peer_deadline=/ { active=1 }
    active && /^if \[ -z "\$PEERED_S" \]; then/ { exit }
    active { print }
' "$subject" > "$fixture/loop"
[[ -s $fixture/loop ]] || { echo 'join-peer-scan: loop missing' >&2; exit 1; }
cat > "$fixture/jsonq" <<'QUERY'
#!/usr/bin/env bash
set -eu
if [[ ${JOIN_TRACE:-1} == 1 ]]; then printf '%s\n' "$*" >> "$fixture/queries"; fi
exec "$JOIN_TEST_JSONQ" "$@"
QUERY
chmod 700 "$fixture/jsonq"
cat > "$fixture/run" <<'RUN'
set -euo pipefail
ZCL_JSONQ=$fixture/jsonq
PEER_ONION=target.onion
PEER_ENDPOINT=target.onion:8033
PEER_WAIT=0 STEP_BUDGET=60 T0=100 ISO_NODE_PID=''
cli() { cat "$fixture/peers"; }
jsonq_get() { "$ZCL_JSONQ" get "$1" 2>/dev/null || true; }
now_s() { printf '100\n'; }
elapsed() { printf '3\n'; }
defect() { echo 'join-peer-scan: unexpected defect' >&2; exit 1; }
sleep() { echo 'join-peer-scan: unexpected sleep' >&2; exit 1; }
for ((iteration=0; iteration<${JOIN_REPEATS:-1}; iteration++)); do
    PEERED_S=''
    . "$fixture/loop"
    printf '%s|%s|%s\n' "$PEER_ID" "$PEER_HEIGHT" "$PEERED_S"
done
RUN

if [[ $bench == 1 ]]; then
    # Frozen synthetic response: 64 unrelated peers with diagnostic padding,
    # then the named peer. Time includes the same CLI and JSON parser work.
    awk 'BEGIN {
        printf "["
        for (i=0; i<64; i++)
            printf "{\"addr\":\"other%d.onion:8033\",\"version\":170012,\"diagnostic\":\"%02000d\"},", i, 0
        print "{\"addr\":\"target.onion:8033\",\"version\":170012,\"id\":77,\"startingheight\":123456}]"
    }' > "$fixture/peers"
    printf 'join-peer-scan: 10 polls, 65 peers, %s bytes per response\n' "$(wc -c < "$fixture/peers")"
    JOIN_TRACE=0 JOIN_REPEATS=10 time -p bash "$fixture/run" > /dev/null
    exit 0
fi

budget_failures=0
check() {
    local label=$1 expected=$2 queries=$3 actual
    printf '%s\n' "$4" > "$fixture/peers"
    : > "$fixture/queries"
    actual=$(bash "$fixture/run")
    [[ $actual == "$expected" ]] || {
        printf 'join-peer-scan: %s got %s expected %s\n' "$label" "$actual" "$expected" >&2
        exit 1
    }
    [[ $(wc -l < "$fixture/queries") == "$queries" ]] || {
        printf 'join-peer-scan: %s exceeded query budget %s:\n' "$label" "$queries" >&2
        cat "$fixture/queries" >&2
        budget_failures=$((budget_failures + 1))
    }
}
check unrelated '||' 3 '[{"addr":"other.onion","version":170012},{"addr":"else.onion","version":170012}]'
check empty '||' 1 '[]'
check first '7|900|3' 5 '[{"addr":"target.onion:8033","version":170012,"id":7,"startingheight":900},{"addr":"other.onion","version":1}]'
check last '8|901|3' 6 '[{"addr":"other.onion","version":1},{"addr":"target.onion:8033","version":170012,"id":8,"startingheight":901}]'
check handshake '9|902|3' 13 '[{"addr":"target.onion","version":0},{"addr":"target.onion","version":null},{"addr":"target.onion"},{"addr":"target.onion","version":""},{"addr":"target.onion","version":170012,"id":9,"startingheight":902}]'
check envelope '10|903|3' 6 '{"result":[{"addr":"target.onion","version":1,"id":10,"startingheight":903}],"error":null,"id":999}'
check escaped '11|904|3' 5 '[{"addr":"target\u002eonion:8033","version":1,"id":11,"startingheight":904}]'
check malformed '||' 1 '[{"addr":"target.onion","version":1},'
[[ $budget_failures == 0 ]] || {
    printf 'join-peer-scan: selection fixtures passed; %s query budgets failed\n' "$budget_failures" >&2
    exit 1
}
printf 'join-peer-scan: PASS (8 selection fixtures and exact query budgets)\n'
