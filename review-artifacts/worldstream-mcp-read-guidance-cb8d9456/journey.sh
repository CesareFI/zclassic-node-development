#!/bin/bash
set -euo pipefail
umask 077
phase=$1
out=$2
case "$phase" in before|after|after-wallet) ;; *) exit 64 ;; esac
repo=$(pwd -P)
binary=$repo/build/bin/z23-dev
dir=$(mktemp -d "$out/$phase.XXXXXXXX")
cd "$dir"
exec > "$dir/receipt.txt"
printf 'phase=%s uid=%s repo=%s head=%s binary=%s\n' "$phase" "$(id -u)" "$repo" "$(git -C "$repo" rev-parse HEAD)" "$binary"
sha256sum "$binary"
flags=()
if [[ "$phase" == after-wallet ]]; then flags=(--wallet-reads --fleet-writes "--checkout=$repo"); fi
coproc SERVER { exec env XDG_STATE_HOME="$dir/fresh-state" "$binary" mcp serve "${flags[@]}" 2>"$dir/stderr.txt"; }
pid=$SERVER_PID
exec {to_server}>&"${SERVER[1]}" {from_server}<&"${SERVER[0]}"
# Bash retains the original write descriptor until the process exits.
eval "exec ${SERVER[1]}>&-"
trap 'kill "$pid" 2>/dev/null || true' EXIT
roundtrip() {
    local n=$1 query=$2 begin end response
    printf '%s\n' "$query" > "$n.request.json"
    begin=$EPOCHREALTIME
    printf '%s\n' "$query" >&$to_server
    IFS= read -r -t 20 response <&$from_server
    end=$EPOCHREALTIME
    printf '%s\n' "$response" > "$n.response.json"
    jq -e --argjson id "$n" '.id == $id and (.result != null)' "$n.response.json" >/dev/null
    printf 'id=%s bytes=%s elapsed_ms=' "$n" "$(wc -c < "$n.response.json")"
    awk -v start="$begin" -v end="$end" 'BEGIN { printf "%.3f\n", (end-start)*1000 }'
}
call() {
    local id=$1 tool=$2 args=$3
    roundtrip "$id" "$(jq -cn --argjson id "$id" --arg tool "$tool" --argjson args "$args" '{jsonrpc:"2.0",id:$id,method:"tools/call",params:{name:$tool,arguments:$args}}')"
    jq -er '.result.content[0].text|fromjson' "$id.response.json" > "$id.payload.json"
}
roundtrip 1 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"worldstream-read-guidance","version":"1"}}}'
printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}' >&$to_server
roundtrip 2 '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
jq -er '.result.instructions' 1.response.json > initialize.txt
jq -er '.result.tools[]|select(.name=="z23_run")|.description' 2.response.json > run-description.txt
call 3 z23_search '{"query":"fleet.machines"}'
call 4 z23_describe '{"path":"fleet.machines"}'
call 5 z23_run '{"path":"fleet.machines","input":{}}'
call 6 z23_run '{"path":"discover.search","input":{"query":"fleet.machines"}}'
exec {to_server}>&-
wait "$pid"
trap - EXIT
jq -e '.. | objects | select(.path?=="fleet.machines")' 3.payload.json >/dev/null
jq -e '.. | objects | select(.authority?=="owner" and .effect?=="read")' 4.payload.json >/dev/null
jq -e '.result.isError == true' 5.response.json >/dev/null
jq -e '.ok==false and .error.code=="READ_REFUSED_OWNER_AUTHORITY" and .error.detail=="fleet.machines"' 5.payload.json >/dev/null
jq -e '.result.isError != true' 6.response.json >/dev/null
jq -e '.ok == true and .command == "discover.search"' 6.payload.json >/dev/null
jq -e '.. | objects | select(.path?=="fleet.machines")' 6.payload.json >/dev/null
if [[ "$phase" == before ]]; then
    grep -Fq 'Reads run directly, except wallet-data reads' run-description.txt
    grep -Fq 'Wallet-data reads are refused unless' initialize.txt
else
    for f in initialize.txt run-description.txt; do
        for term in owner "wallet[- ]risk" core-recovery --wallet-reads; do
            grep -Eiq -- "$term" "$f"
        done
    done
fi
printf '%s\n' 'PASS: search, describe owner/read, typed refusal and subsequent permitted discover.search on one STDIO connection.'
