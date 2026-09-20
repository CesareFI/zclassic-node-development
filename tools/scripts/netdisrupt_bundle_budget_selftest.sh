#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise diagnostic capture with an isolated CLI; no node or network.
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
source_file=${1:-"$root/tools/scripts/network_disruption_recovery_stopwatch.sh"}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/zcl-netdisrupt-bundle.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
awk '
    /^capture_failure_bundle\(\) \{/ { copy=1; found++ }
    copy { print }
    copy && /^\}/ { exit }
    END { if (found != 1) exit 1 }
' "$source_file" > "$scratch/capture.sh"
. "$root/tools/scripts/stopwatch_json_lib.sh"
. "$scratch/capture.sh"

# Shorten only the production 20-second deadline, retaining the real forced
# termination grace. Record each call so removing a bound fails the test.
real_timeout=$(command -v timeout)
timeout() {
    [[ $# -ge 3 && $1 == --kill-after=1 && $2 == 20 ]] || return 2
    printf 'bounded\n' >> "$scratch/bounds"
    shift 2
    "$real_timeout" --kill-after=1 0.1 "$@"
}
NODE_BIN="$scratch/client"
CLIENT_RPCPORT=12345
CLIENT_DATADIR="$scratch/client data"
ARTIFACT_DIR="$scratch/artifacts"
mkdir -p "$CLIENT_DATADIR" "$ARTIFACT_DIR"
export BUNDLE_FIXTURE_ROOT="$scratch"
cat > "$NODE_BIN" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# -ge 4 && $1 == -rpcport=12345 &&
   $2 == "-datadir=$BUNDLE_FIXTURE_ROOT/client data" ]] || exit 9
shift 2
case "$*" in
    'dumpstate reducer_frontier')
        if [[ $BUNDLE_FIXTURE_MODE == busy ]]; then
            printf '{"snapshot_status":"progress_store_busy","retryable":true}\n'
        else
            printf '{"hstar":123,"network_tip":456}\n'
        fi ;;
    'dumpstate blocker') printf '{"active_count":0}\n' ;;
    'ops logs --pattern=. --since_secs=3600 --max_lines=500 --level=all')
        printf 'fixture remote log\n' ;;
    *) exit 9 ;;
esac
case "$BUNDLE_FIXTURE_MODE" in
    failure|fallback) exit 7 ;;
    stalled)
        trap '' TERM
        # Builtin wait avoids leaving a fixture grandchild behind.
        read -r -t 2 line <> "$BUNDLE_FIXTURE_ROOT/wait" || :
        printf 'escaped\n' >> "$BUNDLE_FIXTURE_ROOT/escaped"
        ;;
esac
SH
chmod +x "$NODE_BIN"
mkfifo "$scratch/wait"
failures=0
check() {
    if ! "$@"; then
        printf 'FAIL: %s\n' "$*" >&2
        failures=$((failures + 1))
    fi
}
for BUNDLE_FIXTURE_MODE in success busy failure fallback stalled; do
    export BUNDLE_FIXTURE_MODE
    : > "$scratch/bounds"
    rm -f "$CLIENT_DATADIR/node.log"
    if [[ $BUNDLE_FIXTURE_MODE == fallback ]]; then
        printf 'fixture local log\n' > "$CLIENT_DATADIR/node.log"
    fi
    started=$(date +%s%N)
    capture_failure_bundle
    finished=$(date +%s%N)
    printf 'bundle-budget: case=%s elapsed_ms=%s failed=%s busy=%s\n' \
        "$BUNDLE_FIXTURE_MODE" "$(((finished - started) / 1000000))" \
        "$BUNDLE_CAPTURE_FAILED" "$FRONTIER_BUSY_AT_CAPTURE"
    bounds=$(wc -l < "$scratch/bounds")
    check test "$bounds" -eq 3
    case "$BUNDLE_FIXTURE_MODE" in
        success|busy) check test "$BUNDLE_CAPTURE_FAILED" = false ;;
        *) check test "$BUNDLE_CAPTURE_FAILED" = true ;;
    esac
    if [[ $BUNDLE_FIXTURE_MODE == busy ]]; then
        check test "$FRONTIER_BUSY_AT_CAPTURE" = true
    else
        check test "$FRONTIER_BUSY_AT_CAPTURE" = false
    fi
    if [[ $BUNDLE_FIXTURE_MODE == success ]]; then
        check test "$(<"$ARTIFACT_DIR/frontier.json")" = '{"hstar":123,"network_tip":456}'
        check test "$(<"$ARTIFACT_DIR/blocker.json")" = '{"active_count":0}'
        check test "$(<"$ARTIFACT_DIR/ops.log.tail.txt")" = 'fixture remote log'
    elif [[ $BUNDLE_FIXTURE_MODE == fallback ]]; then
        check test "$(<"$ARTIFACT_DIR/ops.log.tail.txt")" = 'fixture local log'
    fi
done
check test ! -e "$scratch/escaped"
NODE_BIN="$scratch/absent"
capture_failure_bundle
check test "$BUNDLE_CAPTURE_FAILED" = true
[[ $failures == 0 ]] || exit 1
echo 'netdisrupt-bundle-budget-selftest: PASS'
