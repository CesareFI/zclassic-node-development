#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Hermetic sync-observer scalar regression and optional process-cost benchmark.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="${SOAK_ASSERT_SOURCE:-$ROOT/tools/scripts/soak_assert.sh}"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/soak-fields.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
# Extract only the readers; never start the observer or contact a node.
sed -n '/^json_.*() {/,/^}/p' "$SOURCE" > "$scratch/readers.sh"
source "$scratch/readers.sh"

old_num() {
    printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*-?[0-9]+" |
        head -1 | sed -E 's/.*:[ ]*//' || true
}
old_bool() {
    printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*(true|false)" |
        head -1 | sed -E 's/.*:[ ]*//' || true
}
fail() { printf 'soak-fields: %s\n' "$*" >&2; exit 1; }
fixtures=(
    '{}' '{"field":null}' '{"field":-}' '{"field":true}'
    '{"field":false}' '{"field":trueish}' '{"field":false,"field":true}'
    '{"field":0}' '{"field":-7}' '{"field":0007}'
    '{"field":18446744073709551615}' '{"field":12.5}'
    '{"field_next":99,"field":8,"field":9}'
    '{"field":null,"field":17}' '{"field":null,"field":false}'
    $'{"field"\t :  \t-17}' $'{"field"\r\v\f: \t false}'
    $'{"field"\n:7}' $'{"field":\ntrue}'
    $'{"field":3}\n{"field":4}' $'{"field":null}\n{"field":true}'
)
for kind in num bool; do
    for doc in "${fixtures[@]}"; do
        expected=$("old_$kind" "$doc" field)
        actual=$("json_$kind" "$doc" field)
        [[ "$actual" == "$expected" ]] || fail "$kind mismatch for $(printf '%q' "$doc")"
    done
done

if [[ "${1:-}" == --bench ]]; then
    # One poll has three numeric reads and one known-lag boolean read.
    # Wall timings include the caller's existing command substitutions.
    for reader in old json; do
        TIMEFORMAT="$reader: %3R seconds for 200 synthetic polls"
        time for ((i=0; i<200; i++)); do
            a=$("${reader}_num" '{"peer_count":8,"magicbean_peer_count":2}' peer_count)
            b=$("${reader}_num" '{"peer_count":8,"magicbean_peer_count":2}' magicbean_peer_count)
            c=$("${reader}_num" '{"mirror_lag":4,"mirror_lag_known":true}' mirror_lag)
            d=$("${reader}_bool" '{"mirror_lag":4,"mirror_lag_known":true}' mirror_lag_known)
            [[ "$a,$b,$c,$d" == 8,2,4,true ]] || fail 'benchmark values'
        done
    done
fi

# A deterministic regression: readers must work without any external program.
(
    PATH="$scratch/no-executables"
    [[ $(json_num '{"field":42}' field) == 42 ]] || fail 'numeric reader needs an external tool'
    [[ $(json_bool '{"field":false}' field) == false ]] || fail 'boolean reader needs an external tool'
    [[ -z $(json_num '{}' field) ]] || fail 'missing numeric field'
    [[ -z $(json_bool '{}' field) ]] || fail 'missing boolean field'
)
printf 'soak-fields: scalar equivalence and zero external parser processes PASS\n'

# Run the complete observer for one simulated poll. All external observations
# and time are fixtures; no network, service manager, node or datadir is used.
mkdir "$scratch/bin"
cat > "$scratch/bin/date" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == +%s ]]; then
    n=100
    [[ ! -f "$SOAK_TEST_CLOCK" ]] || read -r n < "$SOAK_TEST_CLOCK"
    printf '%s\n' "$((n + 1))" > "$SOAK_TEST_CLOCK"
    printf '%s\n' "$n"
else
    printf 'fixture-time\n'
fi
SH
cat > "$scratch/bin/systemctl" <<'SH'
#!/usr/bin/env bash
if [[ -f "$SOAK_TEST_CLOCK.restart" ]]; then
    printf '%s\n' "${SOAK_TEST_RESTARTS:-1}"
else
    : > "$SOAK_TEST_CLOCK.restart"
    printf '1\n'
fi
SH
cat > "$scratch/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$SOAK_TEST_HEALTH"
SH
cat > "$scratch/bin/rpc" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$SOAK_TEST_SYNC"
SH
cat > "$scratch/bin/sleep" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$scratch/bin/"*
poll() {
    local expected_rc=$1 token=$2 health=$3 sync=$4 restarts=${5:-1} rc=0 output
    rm -f "$scratch/clock" "$scratch/clock.restart"
    output=$(PATH="$scratch/bin:$PATH" SOAK_TEST_CLOCK="$scratch/clock" \
        SOAK_TEST_HEALTH="$health" SOAK_TEST_SYNC="$sync" SOAK_TEST_RESTARTS="$restarts" \
        ZCL_CLI="$scratch/bin/rpc" MIN_PEERS=3 LAG_BREACH_BLOCKS=10 \
        bash "$SOURCE" 3 0 2>&1) || rc=$?
    [[ "$rc" == "$expected_rc" && "$output" == *"$token"* ]] ||
        fail "poll expected $expected_rc/$token, got $rc: $output"
}
health='{"peer_count":8,"magicbean_peer_count":2}'
sync='{"mirror_lag":4,"mirror_lag_known":true,"mirror_lag_breach_severity":"none"}'
poll 0 'soak PASS' "$health" "$sync"
poll 0 'soak PASS' "$health" "${sync/mirror_lag_known/lag_known}"
poll 1 'mirror_lag_unknown' "$health" "${sync/true/false}"
poll 1 'mirror_lag_unknown' "$health" '{}'
poll 1 'lag=14>10' "$health" "${sync/:4/:14}"
poll 1 'peers=-1<3' '{}' "$sync"
poll 1 'severity=warning' "$health" "${sync/none/warning}"
poll 1 'restart_count=2' "$health" "$sync" 2
poll 1 'magicbean_peer_count=0' "${health/:2/:0}" "$sync"
printf 'soak-fields: nine complete observer verdict fixtures PASS\n'
