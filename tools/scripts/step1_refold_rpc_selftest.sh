#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise only the refold observer with local fake RPC clients. No node,
# network or datadir is opened. Optional argument selects a baseline script.
set -euo pipefail
script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
source_file=${1:-$script_dir/step1_refold_rate_proof.sh}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-refold-rpc.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
failures=0
fail() { printf 'refold-rpc: FAIL %s\n' "$*" >&2; failures=$((failures + 1)); }

# Never source the live entry point. Require all three extracted functions.
sed -n '/^rpc() {/,/^}/p; /^_hstar_from() {/,/^}/p; /^read_hstar() {/,/^}/p' \
    "$source_file" > "$fixture/observer.sh"
. "$fixture/observer.sh"
declare -F rpc _hstar_from read_hstar >/dev/null

# Grade the configured bound, not a wall-clock threshold on a loaded host.
# Still execute real timeout below to prove TERM-resistant children are reaped.
timeout() {
    printf '%s %s\n' "${1:-}" "${2:-}" >> "$fixture/timeouts"
    command timeout "$@"
}

cat > "$fixture/client" <<'CLIENT'
#!/usr/bin/env bash
set -eu
[[ $HOME == "$REFOLD_FIXTURE/home" ]]
if [[ ${1:-} == -datadir=* ]]; then
    [[ $1 == "-datadir=$REFOLD_FIXTURE/copy" && $2 == -rpcport=39240 ]]
    shift 2
else
    [[ $ZCL_DATADIR == "$REFOLD_FIXTURE/copy" && $ZCL_RPCPORT == 39240 ]]
fi
[[ $# == 2 && $1 == dumpstate ]]
printf '%s\n' "$2" >> "$REFOLD_FIXTURE/calls"
case "$REFOLD_MODE" in
    ok) printf '{"hstar":42}\n' ;;
    empty) : ;;
    failure) exit 7 ;;
    partial) printf '{"hstar":999}\n'; exit 7 ;;
    fallback)
        if [[ $2 == reducer_frontier ]]; then
            printf '{"hstar":999}\n'; exit 7
        fi
        [[ $2 == '"reducer_frontier"' ]]
        printf '{"hstar":73}\n'
        ;;
    stall)
        trap '' TERM
        printf '{"hstar":999}\n'
        # Finite even on the unbounded baseline; also exercises kill-after.
        sleep 8
        ;;
    *) exit 8 ;;
esac
CLIENT
chmod +x "$fixture/client"
cp "$fixture/client" "$fixture/standalone"
export REFOLD_FIXTURE=$fixture REFOLD_MODE=ok
BIN=$fixture/client ISO_HOME=$fixture/home DATADIR=$fixture/copy RPCPORT=39240

for client in native standalone; do
    RPCBIN=$fixture/client
    [[ $client != standalone ]] || RPCBIN=$fixture/standalone
    for REFOLD_MODE in ok empty failure partial fallback; do
        : > "$fixture/calls"
        : > "$fixture/timeouts"
        got=$(read_hstar 2> "$fixture/err")
        expected='' calls=2
        case "$REFOLD_MODE" in
            ok) expected=42 calls=1 ;;
            fallback) expected=73 ;;
        esac
        [[ $got == "$expected" ]] || fail "$client/$REFOLD_MODE height=<$got> expected=<$expected>"
        [[ $(wc -l < "$fixture/calls") == "$calls" ]] || fail "$client/$REFOLD_MODE fallback count"
        [[ $(wc -l < "$fixture/timeouts") == "$calls" ]] || fail "$client/$REFOLD_MODE unbounded invocation"
        while IFS= read -r bound; do
            [[ $bound == '--kill-after=1 5' ]] || fail "$client/$REFOLD_MODE wrong timeout bound"
        done < "$fixture/timeouts"
        case "$REFOLD_MODE" in
            failure|partial|fallback)
                [[ -s $fixture/err ]] || fail "$client/$REFOLD_MODE lacks failure context" ;;
        esac
    done
    REFOLD_MODE=stall
    SECONDS=0
    got=$(rpc dumpstate reducer_frontier 2> "$fixture/err")
    elapsed=$SECONDS
    printf 'refold-rpc: %s TERM-resistant observation elapsed=%ss output_bytes=%s\n' \
        "$client" "$elapsed" "${#got}"
    [[ -z $got ]] || fail "$client timeout exposed a partial height"
    [[ -s $fixture/err ]] || fail "$client timeout lacks failure context"
    # Recover on the next observation; no stale response or poisoned state.
    REFOLD_MODE=ok
    [[ $(read_hstar) == 42 ]] || fail "$client recovery"
done
[[ $failures == 0 ]] || exit 1
printf 'refold-rpc: PASS successful, empty, failed, partial, fallback, timeout and recovery observations\n'
