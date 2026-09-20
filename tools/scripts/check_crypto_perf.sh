#!/usr/bin/env bash
# check_crypto_perf.sh — the STANDING crypto-vs-Rust performance gate.
#
# Measures every C crypto primitive on the consensus path live (median ns/op,
# via build/bin/zclassic23 -bench-crypto-vs-rust) and enforces two invariants
# against the pinned baseline (tools/crypto_perf_baseline.csv):
#
#   RATCHET (always, hard):  measured_c_ns <= c_ns_baseline * (1 + margin).
#           The baseline is a CEILING that may only shrink — a self-regression
#           beyond the flake margin FAILS. This is the core protection: our C
#           crypto can only get faster.
#
#   RATIO vs Rust:
#     gate_mode=beat   -> hard-FAIL if measured_c_ns >= rust_ns_baseline. We
#                         beat Rust here and must stay ahead. Flake-proof by
#                         construction: a `beat` row is only valid when
#                         rust_ns_baseline >= c_ns_baseline*(1+margin), so any
#                         run that passes the ratchet is necessarily < rust.
#     gate_mode=behind -> NO hard fail (would red main today); prints a loud
#                         "BEHIND RUST — optimize" line and leans on the ratchet
#                         for monotonic improvement toward parity.
#
# This gate is a DELIBERATE target, NOT part of the default `make lint` aggregate
# (microbench timing flakes under CI load). Run it in a quiet context:
#     make check-crypto-perf                # measure + gate + append history
#     tools/scripts/check_crypto_perf.sh --selftest   # logic self-test, no build
#
# Rules honoured: no Rust is linked into the shipped binary (comparison is
# against pinned/cited numbers only); monotonic clock inside the bench; timing
# uses median-of-N for flake resistance.
#
# Exit: 0 = all invariants hold (behind rows are allowed), non-zero = a ratchet
# regression or a lost lead against Rust.
set -euo pipefail

MARGIN="${ZCL_CRYPTO_PERF_MARGIN:-0.20}"
BINARY="${ZCL_CRYPTO_PERF_BIN:-build/bin/zclassic23}"
BASELINE="${ZCL_CRYPTO_PERF_BASELINE:-tools/crypto_perf_baseline.csv}"
HISTORY="${ZCL_BENCH_HISTORY:-docs/bench-history.csv}"
SELFTEST=0

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
    case "$arg" in
        --selftest) SELFTEST=1 ;;
        --margin=*) MARGIN="${arg#*=}" ;;
        --binary=*) BINARY="${arg#*=}" ;;
        --baseline=*) BASELINE="${arg#*=}" ;;
        --history=*) HISTORY="${arg#*=}" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

# eval_row KEY MEAS C_BASE RUST MODE MARGIN
# Echoes: "<verdict> <ratio>" where verdict in
#   OK_BEAT | OK_BEHIND | FAIL_RATCHET | FAIL_BEAT | FAIL_CONFIG
# Returns 0 for OK_*, 1 for FAIL_*. Pure arithmetic — shared by gate + selftest.
eval_row() {
    # Keep both historical four-decimal rounding steps at the ratchet boundary.
    # Combining the arithmetic must not change a gate threshold or its verdict
    # precedence: lost lead, self-regression, then mis-pinned headroom.
    awk -v meas="$2" -v cbase="$3" -v rust="$4" -v mode="$5" -v margin="$6" '
        BEGIN {
            factor = sprintf("%.4f", 1 + margin)
            ceiling = sprintf("%.4f", cbase * factor) + 0
            ratio = sprintf("%.4f", (rust == 0) ? 0 : meas / rust)
            if (mode == "beat" && !(meas < rust))
                verdict = "FAIL_BEAT"
            else if (!(meas <= ceiling))
                verdict = "FAIL_RATCHET"
            else if (mode == "beat" && !(ceiling <= rust))
                verdict = "FAIL_CONFIG"
            else
                verdict = (mode == "beat") ? "OK_BEAT" : "OK_BEHIND"
            print verdict " " ratio
            exit (verdict ~ /^FAIL_/)
        }'
}

# ── selftest: exercise the evaluator against synthetic rows ─────────────
if [ "$SELFTEST" = 1 ]; then
    echo "check_crypto_perf --selftest (evaluator logic, no build)"
    fails=0
    checks=0
    assert() { # DESC EXPECT KEY MEAS CBASE RUST MODE [MARGIN]
        local desc="$1" expect="$2"; shift 2
        local out rc=0 expected_rc=0
        out=$(eval_row "$1" "$2" "$3" "$4" "$5" "${6:-0.20}") || rc=$?
        case "$expect" in FAIL_*) expected_rc=1 ;; esac
        checks=$((checks+1))
        if [ "$out" = "$expect" ] && [ "$rc" -eq "$expected_rc" ]; then
            printf "  OK   %-42s -> %s\n" "$desc" "$out"
        else
            printf "  FAIL %-42s -> %s rc=%s (expected %s rc=%s)\n" \
                "$desc" "$out" "$rc" "$expect" "$expected_rc"
            fails=$((fails+1))
        fi
    }
    #      desc                                     expect        key  meas  cbase  rust    mode
    assert "beat, at baseline, well under rust"     'OK_BEAT 0.5000'      k 100 100 200 beat
    assert "beat, +15% (within margin), under rust" 'OK_BEAT 0.5750'      k 115 100 200 beat
    assert "beat, +25% self-regression"             'FAIL_RATCHET 0.6250' k 125 100 200 beat
    assert "beat, faster than baseline"            'OK_BEAT 0.4000'      k  80 100 200 beat
    assert "beat, but lost lead (meas>=rust)"       'FAIL_BEAT 1.0417'    k 125 100 120 beat
    assert "beat, mis-pinned (no headroom vs rust)" 'FAIL_CONFIG 0.9091'  k 100 100 110 beat
    assert "behind, within ratchet, slower than rust" 'OK_BEHIND 2.7500' k 110 100  40 behind
    assert "behind, self-regression beyond margin" 'FAIL_RATCHET 3.2500' k 130 100  40 behind
    assert "behind, we happen to be ahead"         'OK_BEHIND 0.4500'    k  90 100 200 behind
    assert "ratchet equality passes"               'OK_BEAT 0.6000'      k 120 100 200 beat
    assert "ratchet excess refuses"                'FAIL_RATCHET 0.6000' k 120.00001 100 200 beat
    assert "equal Rust time loses lead"            'FAIL_BEAT 1.0000'    k 120 100 120 beat
    assert "headroom equality passes"              'OK_BEAT 0.8333'      k 100 100 120 beat
    assert "ratio display cannot lose lead"        'OK_BEAT 1.0000'      k 119.99999 100 120 beat
    assert "rounded margin retains ceiling"        'FAIL_RATCHET 0.6000' k 120.001 100 200 behind 0.200049
    assert "rounded product retains ceiling"       'OK_BEHIND 0.6000'    k 1.2001 1.00008 2 behind
    assert "zero reference retains zero ratio"     'OK_BEHIND 0.0000'    k 100 100 0 behind
    if [ "$fails" -eq 0 ]; then
        echo "check_crypto_perf selftest: OK ($checks/$checks)"
        exit 0
    fi
    echo "check_crypto_perf selftest: FAIL ($fails failing case(s))"
    exit 1
fi

# ── live gate ───────────────────────────────────────────────────────────
[ -f "$BASELINE" ] || { echo "baseline not found: $BASELINE" >&2; exit 2; }
[ -x "$BINARY" ]   || { echo "binary not found/executable: $BINARY (build first: make zclassic23)" >&2; exit 2; }

echo "crypto-perf gate: measuring $BINARY (margin=$MARGIN, history=$HISTORY)"
MEAS_RAW="$(ZCL_BENCH_HISTORY="$HISTORY" "$BINARY" -bench-crypto-vs-rust 2>/dev/null || true)"

# key -> measured c_ns
declare -A MEAS
while read -r _tag key ns _ops; do
    [ "$_tag" = "CRYPTOPERF" ] || continue
    MEAS["$key"]="$ns"
done <<< "$(echo "$MEAS_RAW" | grep '^CRYPTOPERF ' || true)"

if [ "${#MEAS[@]}" -eq 0 ]; then
    echo "FATAL: bench produced no CRYPTOPERF rows (teeth refused everything?)" >&2
    echo "$MEAS_RAW" | tail -20 >&2
    exit 1
fi

printf "\n%-26s %12s %12s %8s %-8s %s\n" primitive c_ns rust_ns ratio mode verdict
printf -- "---------------------------------------------------------------------------------\n"

fails=0; skipped=0; behind=0; measured=0
while IFS=, read -r primitive cbase rust mode rust_source notes; do
    case "$primitive" in ''|'#'*|primitive) continue ;; esac
    m="${MEAS[$primitive]:-}"
    if [ -z "$m" ]; then
        printf "%-26s %12s %12s %8s %-8s %s\n" "$primitive" "-" "$rust" "-" "$mode" "SKIP (not measured — params absent?)"
        skipped=$((skipped+1)); continue
    fi
    measured=$((measured+1))
    out=$(eval_row "$primitive" "$m" "$cbase" "$rust" "$mode" "$MARGIN") && rc=0 || rc=1
    verdict="${out%% *}"; ratio="${out##* }"
    case "$verdict" in
        OK_BEAT)      tag="BEAT (ahead of rust)";;
        OK_BEHIND)    tag="behind — ratchet holds"; behind=$((behind+1));;
        FAIL_RATCHET) tag="*** FAIL: self-regression > margin ***";;
        FAIL_BEAT)    tag="*** FAIL: lost lead vs rust (ratio>=1) ***";;
        FAIL_CONFIG)  tag="*** FAIL: beat row mis-pinned (no ratchet headroom vs rust) ***";;
        *)            tag="?";;
    esac
    printf "%-26s %12s %12s %8s %-8s %s\n" "$primitive" "$m" "$rust" "$ratio" "$mode" "$tag"
    [ "$rc" -ne 0 ] && fails=$((fails+1))
    if [ "$verdict" = "OK_BEHIND" ]; then
        echo "    BEHIND RUST — optimize $primitive (ratio ${ratio}x; $rust_source)"
    fi
done < "$BASELINE"

printf -- "---------------------------------------------------------------------------------\n"
echo "measured=$measured  behind=$behind  skipped=$skipped  fails=$fails  (margin=$MARGIN)"

if [ "$fails" -ne 0 ]; then
    echo "check-crypto-perf: FAIL — $fails primitive(s) violated the ratchet or lost the lead."
    exit 1
fi
echo "check-crypto-perf: OK — no self-regression, no lost lead. Behind-rust rows are ratchet-tracked."
exit 0
