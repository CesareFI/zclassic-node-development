#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic collector escaping regression and optional instrumentation benchmark.
# Usage: bash tools/scripts/netdisrupt_record_escape_selftest.sh [--bench] [collector]
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
if (( $# > 1 )); then
    printf 'usage: %s [--bench] [collector]\n' "$0" >&2
    exit 2
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
collector=${1:-$script_dir/netdisrupt_stopwatch_run_and_record.sh}
fixture=$(mktemp -d /tmp/zcl-netdisrupt-escape.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Load only the formatter, without running a stopwatch or touching a ledger.
awk '/^json_escape\(\)/ {copy=1} /^json_num_or_null\(\)/ {copy=0}
     copy {print}' "$collector" >"$fixture/formatter.sh"
. "$fixture/formatter.sh"
legacy_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g' | tr '\n' ' '
}
check() {
    local value=$1 expected actual
    expected=$(legacy_escape "$value")
    actual=$(json_escape "$value")
    [[ $actual == "$expected" ]] || { echo 'FAIL: escaped bytes changed' >&2; exit 1; }
    actual=$(json_string "$value")
    [[ $actual == "\"$expected\"" ]] || { echo 'FAIL: quoted bytes changed' >&2; exit 1; }
}
values=('' 'plain' 'space and /path' '"quoted"' '\\backslash\'
        '& replacement & /' '$(false) `false` * ? [x]' 'Unicode: é λ'
        $'\t\r\n' $'\n\nleading\nembedded\ntrailing\n\n' 'literal\t\r\n'
        $'mixed\\"\t\r\nend')
for value in "${values[@]}"; do check "$value"; done
printf -v large '%16384s' ''
check "$large${values[11]}$large"
echo 'netdisrupt-record-escape: byte compatibility PASS (13 cases)'

if (( bench )); then
    TIMEFORMAT='netdisrupt-record-escape: 100 ledger string batches: wall=%3R user=%3U sys=%3S seconds'
    for ((trial=0; trial<3; trial++)); do
        time for ((i=0; i<100; i++)); do
            for value in pass '127.0.0.1:18252' '/fixture/node' c1f7863d0 \
                         '/fixture/artifact' '' ''; do
                json_string "$value" >/dev/null
            done
        done
    done
fi

# A deterministic cost gate: string emission must not launch parser programs.
(
    PATH=/nonexistent
    actual=$(json_string $'a\\b"c\t\r\n')
    [[ $actual == '"a\\b\"c\t\r "' ]] || { echo 'FAIL: builtin formatter' >&2; exit 1; }
)
echo 'netdisrupt-record-escape: no external parser programs PASS'

# Exercise the real collector with a canned stopwatch in an isolated tree.
# No peer, process signal, node binary or operator ledger is used. The missing
# optional classifier deliberately exercises its documented fallback path.
mkdir -p "$fixture/tools/scripts" "$fixture/bin"
cp "$collector" "$fixture/tools/scripts/netdisrupt_stopwatch_run_and_record.sh"
cat >"$fixture/tools/scripts/network_disruption_recovery_stopwatch.sh" <<'MOCK'
printf 'WALL_CLOCK_SECONDS=42\n'
printf 'netdisrupt-stopwatch: artifact=/fixture/artifact\n'
exit "$TEST_STOPWATCH_RC"
MOCK
cat >"$fixture/bin/date" <<'MOCK'
#!/usr/bin/env bash
printf '2000000000\n'
MOCK
cat >"$fixture/bin/git" <<'MOCK'
#!/usr/bin/env bash
printf 'fixture-commit\n'
MOCK
chmod +x "$fixture/bin/date" "$fixture/bin/git"
for rc in 0 1 2 3 4 5 9; do
    case $rc in
        0) verdict=pass ;; 1) verdict=fail ;; 2) verdict=skip ;;
        3) verdict=seam ;; 4) verdict=stalled-named ;;
        5) verdict=frontier-busy-timeout ;; *) verdict=error ;;
    esac
    PATH="$fixture/bin:$PATH" TEST_STOPWATCH_RC=$rc \
        ZCL_ND_NODE_BIN=$'/fixture/a\\b"c\t\r\n' \
        ZCL_ND_CLIENT_RPCPORT=18252 ZCL_ND_CLIENT_DATADIR="$fixture/datadir" \
        ZCL_ND_CUT_SECS=600 ZCL_ND_BUDGET_SECS=600 \
        ZCL_ND_HISTORY_DIR="$fixture/history-$rc" \
        bash "$fixture/tools/scripts/netdisrupt_stopwatch_run_and_record.sh" \
        >"$fixture/output-$rc" 2>&1
    expected='{"ts":2000000000,"verdict":"'"$verdict"'","exit_code":'"$rc"',"wall_clock_seconds":42,"budget_seconds":600,"cut_seconds":600,"peer":"127.0.0.1:18252","node_bin":"/fixture/a\\b\"c\t\r ","build_commit":"fixture-commit","artifact_dir":"/fixture/artifact","skip_reason":"","skip_class":"","skip_streak":0,"no_pass_streak":0}'
    actual=$(cat "$fixture/history-$rc/history.jsonl")
    [[ $actual == "$expected" ]] || { echo "FAIL: collector ledger rc=$rc" >&2; exit 1; }
done
echo 'netdisrupt-record-escape: isolated collector PASS (7 verdicts)'
