#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic replay-canary integer-reader regression and observer-cost benchmark.
# Usage: bash tools/scripts/replay_canary_parser_selftest.sh [--bench] [harness]
set -euo pipefail

bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
harness=${1:-$script_dir/replay_canary.sh}
fixture=$(mktemp -d /tmp/zcl-replay-parser.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Load only the actual reader here, without sourcing the live driver.
sed -n '/^json_num() {/,/^}/p' "$harness" > "$fixture/reader.sh"
. "$fixture/reader.sh"
declare -F json_num >/dev/null
checks=0
failures=0
check_read() {
    local description=$1 document=$2 key=$3 expected=$4 actual rc=0
    actual=$(json_num "$document" "$key") || rc=$?
    checks=$((checks + 1))
    if [ "$actual" != "$expected" ] || [ "$rc" != 0 ]; then
        printf 'FAIL: %s: expected <%s> rc=0, got <%s> rc=%s\n' \
            "$description" "$expected" "$actual" "$rc" >&2
        failures=$((failures + 1))
    fi
}

check_read 'height' '{"verified_height":3107923}' verified_height 3107923
check_read 'zero rejects' '{"total_rejected":0}' total_rejected 0
check_read 'negative sentinel' '{"height":-1}' height -1
check_read 'wide integer remains text' '{"txouts":18446744073709551615}' txouts 18446744073709551615
check_read 'leading zeros remain text' '{"height":00042}' height 00042
check_read 'all line-local whitespace' $'{"height" \t\r\v\f: \t\r\v\f42}' height 42
check_read 'pretty document' $'{\n  "height": 42\n}' height 42
check_read 'similar key' '{"height_next":99,"height":42}' height 42
check_read 'same-line duplicates' '{"height":42,"height":99}' height 42
check_read 'multiline duplicates' $'{"height":42}\n{"height":99}' height 42
check_read 'first integer after noninteger' '{"height":null,"height":"9","height":42}' height 42
check_read 'empty document' '' height ''
check_read 'absent integer' '{"height_next":42}' height ''
check_read 'null' '{"height":null}' height ''
check_read 'string' '{"height":"42"}' height ''
check_read 'boolean' '{"height":false}' height ''
# Preserve the old grep reader's line boundary and numeric-prefix behavior.
# This is an existing field extractor, not a new general JSON validator.
check_read 'newline before colon' $'{"height"\n:42}' height ''
check_read 'newline after colon' $'{"height":\n42}' height ''
check_read 'later complete field after split' $'{"height":\n99,"height":42}' height 42
check_read 'decimal prefix unchanged' '{"height":42.5}' height 42
check_read 'exponent prefix unchanged' '{"height":42e3}' height 42
check_read 'plus sign unchanged' '{"height":+42}' height ''
printf -v padding '%262144s' ''
check_read 'large reply keeps first integer' "{\"height\":42,\"padding\":\"$padding\",\"height\":99}" height 42
printf 'replay parser: %s output/status checks, %s failures\n' "$checks" "$failures"

# Exercise the real verdict entry point as well as the extracted reader.
# Everything, including executable identity and sentinels, is fixture-local.
# Stub host logging and whole-filesystem sync: this checks verdict semantics,
# not journal delivery or crash durability. No node or RPC client is launched.
mkdir -p "$fixture/bin" "$fixture/rpc" "$fixture/verdict"
for tool in logger sync; do
    printf '#!/bin/sh\nexit 0\n' > "$fixture/bin/$tool"
    chmod +x "$fixture/bin/$tool"
done
cat > "$fixture/bin/node" <<'NODE'
#!/bin/sh
[ "$1" = agentbuild ] || exit 2
printf '%s\n' '{"source_id_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","build_commit":"fixture"}'
NODE
chmod +x "$fixture/bin/node"
verdict_checks=0
for scenario in pass genesis rejects anchor_hash height txouts supply skipped fast slow failed timeout exact_hash; do
    from=anchor expected_rc=1 expected_verdict=FAIL expected_reason=''
    state=complete rejected=0 skipped=0 uc_height=3145329
    zd_height=3145329 zd_txouts=1354769 zd_supply=10364137.94674881
    elapsed=600
    hash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    legacy_hash=$hash
    case "$scenario" in
        pass) expected_rc=0; expected_verdict=PASS ;;
        genesis) from=genesis; elapsed=3600; expected_rc=0; expected_verdict=PASS ;;
        rejects) rejected=1; expected_reason=consensus_rejects ;;
        anchor_hash) uc_height=3056758; expected_reason=sha3_mismatch ;;
        height) zd_height=3145330; expected_reason=crossnode_height ;;
        txouts) zd_txouts=1354770; expected_reason=crossnode_txouts ;;
        supply) zd_supply=10364138.94674881; expected_reason=crossnode_supply ;;
        skipped) from=genesis; elapsed=3600; skipped=1; expected_reason=script_verif_skipped_no_undo ;;
        fast) elapsed=5; expected_reason=elapsed_too_fast ;;
        slow) elapsed=99999; expected_reason=elapsed_too_slow ;;
        failed) state=failed; expected_reason=bg_validation_failed ;;
        timeout) state=timeout; expected_rc=2; expected_verdict=BLOCKED; expected_reason=budget_exceeded_incomplete_no_parity_evidence ;;
        exact_hash) legacy_hash=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; expected_reason=crossnode_utxo_sha3 ;;
    esac
    printf '{"state":"%s","verified_height":3145329,"script_verif_skipped_no_undo":%s}\n' \
        "$state" "$skipped" > "$fixture/rpc/getsyncdetail.json"
    printf '{"total_rejected":%s}\n' "$rejected" > "$fixture/rpc/getsyncdiag.json"
    printf '{"sha3_hash":"%s","height":%s}\n' "$hash" "$uc_height" > "$fixture/rpc/getutxocommitment.json"
    printf '%s\n' '{"height":3145329,"bestblock":"abc123","txouts":1354769,"total_amount":"10364137.94674881"}' \
        > "$fixture/rpc/gettxoutsetinfo.json"
    printf '{"height":%s,"bestblock":"abc123","txouts":%s,"total_amount":%s}\n' \
        "$zd_height" "$zd_txouts" "$zd_supply" > "$fixture/rpc/zd_gettxoutsetinfo.json"
    printf '{"legacy_utxo_sha3":"%s","best_block":"abc123"}\n' "$legacy_hash" \
        > "$fixture/rpc/legacy_utxo_commitment.json"
    printf '%s\n' "$elapsed" > "$fixture/rpc/elapsed.json"
    # Remove old output ourselves so a broken driver cannot pass on a prior
    # case's sentinel. The registered C suite separately tests stale resets.
    rm -f "$fixture/verdict/replay_canary_$from.json"
    rc=0
    env -i PATH="$fixture/bin:$PATH" HOME="$fixture" LC_ALL=C \
        ZCL_CANARY_VERDICT_DIR="$fixture/verdict" \
        ZCL_CANARY_SELFTEST_DIR="$fixture/rpc" \
        ZCL_CANARY_SELFTEST_NODE_BIN="$fixture/bin/node" \
        bash "$harness" --from="$from" --self-test=pass > "$fixture/output" 2>&1 || rc=$?
    sentinel=''
    if [ -f "$fixture/verdict/replay_canary_$from.json" ]; then
        sentinel=$(< "$fixture/verdict/replay_canary_$from.json")
    fi
    if [ "$rc" != "$expected_rc" ] ||
       [[ "$sentinel" != *"\"verdict\":\"$expected_verdict\""* ]] ||
       [[ "$sentinel" != *"\"reason\":\"$expected_reason\""* ]]; then
        printf 'FAIL: verdict %s: expected %s/%s rc=%s, got rc=%s <%s>\n' \
            "$scenario" "$expected_verdict" "$expected_reason" "$expected_rc" "$rc" "$sentinel" >&2
        cat "$fixture/output" >&2
        failures=$((failures + 1))
    fi
    verdict_checks=$((verdict_checks + 1))
done
printf 'replay parser: %s verdict scenarios checked\n' "$verdict_checks"

# Deterministic cost gate: the integer reader needs no external executable.
# This also catches future replacements with a different external parser.
if ! (PATH=/nonexistent; value=$(json_num '{"height":42}' height); [ "$value" = 42 ]); then
    echo 'FAIL: integer reader requires an external executable' >&2
    failures=$((failures + 1))
fi

if [ "$bench" = 1 ]; then
    document='{"state":"RUNNING","verified_height":3107923,"tip_height":3190019,"total_rejected":0}'
    for trial in 1 2 3; do
        TIMEFORMAT="trial $trial: 900 reads, wall=%3R s user=%3U s sys=%3S s"
        time for ((i=0; i<300; i++)); do
            for key in verified_height tip_height total_rejected; do
                value=$(json_num "$document" "$key")
                [ -n "$value" ]
            done
        done
    done
fi

if [ "$failures" != 0 ]; then exit 1; fi
echo 'replay-canary-parser: PASS (output/status compatibility, zero external tools)'
