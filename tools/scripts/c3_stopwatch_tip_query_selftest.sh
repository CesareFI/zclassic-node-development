#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the real triple-run tip reader with isolated CLI doubles. No node
# or network participates. The timeout seam shortens only the 20s query budget.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${1:-$ROOT/tools/scripts/c3_stopwatch_triple_run.sh}"
TMP="$(mktemp -d /tmp/zcl-c3-tip-query.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
awk '/^tip_doc\(\) \{/ { copy=1 } copy { print } copy && /^\}/ { exit }' \
    "$SOURCE" > "$TMP/reader.sh"
. "$TMP/reader.sh"
REAL_TIMEOUT="$(command -v timeout)"
timeout() {
    local kill_args=()
    if [[ ${1:-} == --kill-after=* ]]; then
        [[ $1 == --kill-after=1 ]] || return 2
        kill_args+=("$1")
        shift
    fi
    [[ $1 == 20 ]] || return 2
    shift
    "$REAL_TIMEOUT" "${kill_args[@]}" 0.1 "$@"
}
NODE_BIN="$TMP/client"
export TIP_FIXTURE_DIR="$TMP"
cat > "$NODE_BIN" <<'SH'
#!/usr/bin/env bash
set -eu
[[ $# == 5 && $1 == '-datadir=/fixture path' && $2 == -rpcport=12345 &&
   $3 == core && $4 == chain && $5 == tip ]] || exit 9
printf '%s' '{"ok":true,"data":{"height":123,"hash":"fixture"}}'
case "$TIP_FIXTURE_MODE" in
    success) exit 0 ;;
    failure) exit 7 ;;
    stalled)
        trap '' TERM
        sleep 2
        : > "$TIP_FIXTURE_DIR/escaped-deadline"
        ;;
esac
SH
chmod +x "$NODE_BIN"
failures=0
for TIP_FIXTURE_MODE in success failure stalled; do
    export TIP_FIXTURE_MODE
    started=$(date +%s%N)
    output=$(tip_doc '/fixture path' 12345) || true
    ended=$(date +%s%N)
    printf 'tip-query: case=%s elapsed_ms=%s bytes=%s\n' \
        "$TIP_FIXTURE_MODE" "$(((ended - started) / 1000000))" "${#output}"
    if [[ $TIP_FIXTURE_MODE == success ]]; then
        expected='{"ok":true,"data":{"height":123,"hash":"fixture"}}'
        if [[ $output != "$expected" ]]; then
            echo 'FAIL: successful response was not preserved' >&2
            failures=$((failures + 1))
        fi
    elif [[ -n $output ]]; then
        echo "FAIL: $TIP_FIXTURE_MODE output became tip evidence" >&2
        failures=$((failures + 1))
    fi
done
if [[ -e $TMP/escaped-deadline ]]; then
    echo 'FAIL: TERM-resistant query continued beyond the kill grace' >&2
    failures=$((failures + 1))
fi
NODE_BIN="$TMP/absent"
output=$(tip_doc '/fixture path' 12345) || true
[[ -z $output ]] || { echo 'FAIL: missing client produced evidence' >&2; exit 1; }
output=$(tip_doc '' 12345) || true
[[ -z $output ]] || { echo 'FAIL: absent datadir produced evidence' >&2; exit 1; }
[[ $failures == 0 ]] || exit 1
echo 'PASS: successful tip bytes preserved; failed/stalled queries unavailable; forced termination bounded'
