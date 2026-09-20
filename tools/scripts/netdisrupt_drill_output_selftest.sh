#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic recovery-benchmark recording regression; --bench measures parsing.
# Usage: bash tools/scripts/netdisrupt_drill_output_selftest.sh [--bench] [runner]
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
subject=${1:-$script_dir/netdisrupt_two_node_run_and_record.sh}
fixture=$(mktemp -d /tmp/zcl-drill-output.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Extract production parsing only. The optional old source uses its actual
# three pipelines, so the same behavioral and process budget checks apply.
sed -n '/^parse_drill_output() {/,/^}/p' "$subject" > "$fixture/parser.sh"
if [[ ! -s $fixture/parser.sh ]]; then
    printf 'parse_drill_output() {\nlocal out=$1\n' > "$fixture/parser.sh"
    sed -n '/^wall_clock=/,/^peer_desc=/p' "$subject" >> "$fixture/parser.sh"
    printf '}\n' >> "$fixture/parser.sh"
fi
. "$fixture/parser.sh"
check() {
    parse_drill_output "$1"
    [[ $wall_clock == "$2" && $artifact_dir == "$3" && ${follower_rpc:-0} == "$4" ]] || {
        printf 'FAIL parsed fields: <%s> <%s> <%s>\n' \
            "$wall_clock" "$artifact_dir" "$follower_rpc" >&2
        exit 1
    }
}
check '' '' '' 0
check 'unrelated output' '' '' 0
check $'WALL_CLOCK_SECONDS=0012\nnetdisrupt-two-node: artifact=/fixture/a b\\c\nB{dd=/tmp/b p2p=39010 rpc=39011}' \
    0012 '/fixture/a b\c' 39011
check $'WALL_CLOCK_SECONDS=1\nWALL_CLOCK_SECONDS=2\nWALL_CLOCK_SECONDS=bad\nWALL_CLOCK_SECONDS=3 extra\nWALL_CLOCK_SECONDS=\n WALL_CLOCK_SECONDS=9' 2 '' 0
check $'netdisrupt-two-node: artifact=first\nnetdisrupt-two-node: artifact=\nB{dd=/a p2p=1 rpc=2}\nB{dd=/b p2p=1 rpc=}' '' '' 0
check $'prefix B{dd=/a p2p=1 rpc=2} B{dd=/b p2p=3 rpc=4} suffix\nB{dd=/bad path p2p=5 rpc=6}' '' '' 4
check 'B{dd=/a p2p=1 rpc=2} B{dd=/b p2p=3 rpc=bad}' '' '' 2
check $'netdisrupt-two-node: artifact=$(false) `false` * ?\nWALL_CLOCK_SECONDS=42\r\nB{dd= p2p= rpc=0007}' '' '$(false) `false` * ?' 0007
printf -v noise '%262144s' ''
out=$'WALL_CLOCK_SECONDS=4\n'"$noise"$'\nnetdisrupt-two-node: artifact=/fixture/last\nWALL_CLOCK_SECONDS=42\nB{dd=/tmp/b p2p=39010 rpc=39011}'
check "$out" 42 /fixture/last 39011
echo 'drill-output: field compatibility PASS (9 cases)'

if (( bench )); then
    TIMEFORMAT='100 parses of 256 KiB drill output: wall=%3R user=%3U sys=%3S seconds'
    for ((trial=0;trial<3;trial++)); do
        time for ((i=0;i<100;i++)); do parse_drill_output "$out"; done
    done
fi

# Drive the whole runner with an inert drill, deterministic metadata and a
# temporary ledger. No node, signals, credentials or network are involved.
mkdir -p "$fixture/tools/scripts" "$fixture/bin"
cp "$subject" "$fixture/tools/scripts/netdisrupt_two_node_run_and_record.sh"
cat > "$fixture/tools/scripts/netdisrupt_two_node_drill.sh" <<'MOCK'
printf 'WALL_CLOCK_SECONDS=4\nWALL_CLOCK_SECONDS=42\n'
printf 'netdisrupt-two-node: artifact=/fixture/artifact\n'
printf 'B{dd=/tmp/b p2p=39010 rpc=39011}\n'
exit "$TEST_DRILL_RC"
MOCK
cat > "$fixture/bin/date" <<'MOCK'
#!/usr/bin/env bash
printf '2000000000\n'
MOCK
cat > "$fixture/bin/git" <<'MOCK'
#!/usr/bin/env bash
printf 'fixture-commit\n'
MOCK
chmod +x "$fixture/bin/date" "$fixture/bin/git"
for rc in 0 1 2 3 4 9; do
    case $rc in
        0) verdict=pass ;; 1) verdict=fail ;; 2) verdict=skip ;;
        3) verdict=seam ;; 4) verdict=stalled-named ;; *) verdict=error ;;
    esac
    actual_rc=0
    PATH="$fixture/bin:$PATH" TEST_DRILL_RC=$rc ZCL_ND2_NODE_BIN=/fixture/node \
        ZCL_ND2_CUT_SECS=30 ZCL_ND2_BUDGET_SECS=120 \
        ZCL_ND_HISTORY_DIR="$fixture/history-$rc" \
        bash "$fixture/tools/scripts/netdisrupt_two_node_run_and_record.sh" \
        > "$fixture/output-$rc" 2>&1 || actual_rc=$?
    expected_rc=$rc
    [[ $rc != 2 ]] || expected_rc=0
    [[ $actual_rc == "$expected_rc" ]] || { echo 'FAIL runner exit status' >&2; exit 1; }
    expected='{"ts":2000000000,"verdict":"'"$verdict"'","exit_code":'"$rc"',"wall_clock_seconds":42,"budget_seconds":120,"cut_seconds":30,"peer":"127.0.0.1:39011","node_bin":"/fixture/node","build_commit":"fixture-commit","artifact_dir":"/fixture/artifact"}'
    actual=$(< "$fixture/history-$rc/history.jsonl")
    [[ $actual == "$expected" ]] || { echo 'FAIL runner ledger bytes' >&2; exit 1; }
done
echo 'drill-output: isolated runner ledger and verdicts PASS (6 cases)'

awk() { echo awk >> "$fixture/calls"; command awk "$@"; }
sed() { echo sed >> "$fixture/calls"; command sed "$@"; }
tail() { echo tail >> "$fixture/calls"; command tail "$@"; }
: > "$fixture/calls"
parse_drill_output "$out"
calls=$(wc -l < "$fixture/calls")
echo "drill-output: external parser processes=$calls"
[[ $calls == 1 ]] || { echo 'FAIL: expected one parser process per recording' >&2; exit 1; }
echo 'drill-output: process budget PASS'
