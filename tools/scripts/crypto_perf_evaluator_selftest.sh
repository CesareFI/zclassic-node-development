#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Prove one arithmetic process per crypto benchmark row, without a node.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="${CRYPTO_PERF_TEST_GATE:-$ROOT/tools/scripts/check_crypto_perf.sh}"
SCRATCH="$(mktemp -d)"
trap 'rm -rf -- "$SCRATCH"' EXIT
trap 'exit 130' HUP INT TERM
export CRYPTO_PERF_TEST_AWK="$(command -v awk)"
export CRYPTO_PERF_TEST_CALLS="$SCRATCH/calls"
mkdir "$SCRATCH/bin"
cat > "$SCRATCH/bin/awk" <<'EOF'
#!/usr/bin/env bash
printf 'call\n' >> "$CRYPTO_PERF_TEST_CALLS"
exec "$CRYPTO_PERF_TEST_AWK" "$@"
EOF
chmod +x "$SCRATCH/bin/awk"
PATH="$SCRATCH/bin:$PATH" bash "$GATE" --selftest > "$SCRATCH/result"
cat "$SCRATCH/result"
checks="$(grep -c '^  OK ' "$SCRATCH/result")"
calls="$(wc -l < "$SCRATCH/calls")"
if [ "$checks" -eq 0 ] || [ "$calls" -ne "$checks" ]; then
    printf 'FAIL: %s evaluator rows started %s awk processes (expected one per row)\n' \
        "$checks" "$calls" >&2
    exit 1
fi
printf 'crypto-perf evaluator: PASS (%s rows, %s arithmetic processes)\n' "$checks" "$calls"

# Exercise the real CSV/benchmark-output/report path with inert synthetic rows.
# No crypto primitive or node is executed by this fixture.
cat > "$SCRATCH/bench" <<'EOF'
#!/usr/bin/env bash
printf 'CRYPTOPERF fixture %s 1\n' "$CRYPTO_PERF_TEST_MEASURED"
EOF
chmod +x "$SCRATCH/bench"
check_gate() {
    local measured="$1" rust="$2" mode="$3" expected_rc="$4" expected_text="$5" rc=0
    printf 'fixture,100,%s,%s,synthetic,selftest\n' "$rust" "$mode" > "$SCRATCH/baseline.csv"
    CRYPTO_PERF_TEST_MEASURED="$measured" bash "$GATE" --margin=0.20 \
        --binary="$SCRATCH/bench" --baseline="$SCRATCH/baseline.csv" \
        --history="$SCRATCH/history.csv" > "$SCRATCH/report" || rc=$?
    if [ "$rc" -ne "$expected_rc" ] || ! grep -Fq -- "$expected_text" "$SCRATCH/report"; then
        cat "$SCRATCH/report" >&2
        printf 'FAIL: gate fixture %s/%s/%s exited %s (expected %s, %s)\n' \
            "$measured" "$rust" "$mode" "$rc" "$expected_rc" "$expected_text" >&2
        exit 1
    fi
}
check_gate 100 200 beat 0 'BEAT (ahead of rust)'
check_gate 110 40 behind 0 'behind — ratchet holds'
check_gate 125 200 beat 1 'FAIL: self-regression > margin'
check_gate 125 120 beat 1 'FAIL: lost lead vs rust'
check_gate 100 110 beat 1 'FAIL: beat row mis-pinned'
printf 'crypto-perf gate: PASS (five report and exit-status fixtures)\n'

case "${1:-}" in
    '') ;;
    --bench)
        TIMEFORMAT='50 evaluator selftests: %3R seconds'
        time for ((i=0; i<50; i++)); do
            bash "$GATE" --selftest > /dev/null
        done
        ;;
    *) printf 'usage: %s [--bench]\n' "$0" >&2; exit 2 ;;
esac
