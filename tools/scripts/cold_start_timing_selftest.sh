#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the actual startup probe with a private node double and fake clock.
# No chain data, external peer, or production process is used.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture=$(mktemp -d /tmp/z23-cold-start-timing.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/tools/scripts" "$fixture/build/bin" "$fixture/bin"
cp "$repo_root/tools/scripts/cold_start_test.sh" "$fixture/tools/scripts/"
cp "$repo_root/tools/scripts/stopwatch_json_lib.sh" "$fixture/tools/scripts/"
export TIMING_CLOCK="$fixture/clock" TIMING_READY="$fixture/ready"
export TIMING_REAL_GREP
TIMING_REAL_GREP=$(command -v grep)

cat > "$fixture/bin/date" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == '+%s' ]] || exit 1
cat "$TIMING_CLOCK"
SH
cat > "$fixture/bin/grep" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# Wait for fixture startup, then model a log scan completing at a known time.
for ((attempt=0; attempt<500; attempt++)); do
    [[ -f "$TIMING_READY" ]] && break
    sleep 0.01
done
[[ -f "$TIMING_READY" ]] || exit 1
printf '%s\n' "$TIMING_OBSERVED_AT" > "$TIMING_CLOCK"
exec "$TIMING_REAL_GREP" "$@"
SH
cat > "$fixture/build/bin/zclassic23" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "-load-snapshot-at-own-height: coin set RE-SEEDED count=$TIMING_COUNT"
touch "$TIMING_READY"
exec sleep 60
SH
printf '#!/bin/sh\nexit 1\n' > "$fixture/build/bin/zcl-rpc"
chmod +x "$fixture/bin/"* "$fixture/build/bin/"*
# Sparse, local public-fixture doubles; the node double never reads them.
truncate -s 10485761 "$fixture/block_index.bin" "$fixture/utxo.snapshot"

failures=0
run_case() {
    local name="$1" observed_at="$2" count="$3" expected_rc="$4" expected_text="$5"
    local rc=0
    rm -f "$TIMING_READY"
    printf '100\n' > "$TIMING_CLOCK"
    PATH="$fixture/bin:$PATH" \
        TIMING_OBSERVED_AT="$observed_at" TIMING_COUNT="$count" \
        ZCL_C3_BUNDLE_SNAPSHOT="$fixture/utxo.snapshot" \
        ZCL_C3_BLOCK_INDEX="$fixture/block_index.bin" \
        DEADLINE_SECS=90 MIN_UTXOS=1000000 \
        bash "$fixture/tools/scripts/cold_start_test.sh" > "$fixture/output" 2>&1 || rc=$?
    if [[ "$rc" == "$expected_rc" ]] &&
       "$TIMING_REAL_GREP" -Fq -- "$expected_text" "$fixture/output"; then
        printf 'PASS: %s\n' "$name"
    else
        printf 'FAIL: %s (expected rc=%s and <%s>, got rc=%s)\n' \
            "$name" "$expected_rc" "$expected_text" "$rc" >&2
        cat "$fixture/output" >&2
        failures=$((failures + 1))
    fi
}

run_case 'scan latency included in startup time' 189 1000001 0 'elapsed=89s utxos=1000001'
run_case 'observation at the exclusive deadline refused' 190 1000001 1 'TIMEOUT after 90s'
run_case 'observation after the deadline refused' 191 1000001 1 'TIMEOUT after 91s'
run_case 'count at threshold still refused' 101 1000000 1 'below threshold 1000000'
run_case 'count below threshold still refused' 101 999999 1 'below threshold 1000000'
[[ "$failures" == 0 ]] || exit 1
printf 'cold-start timing: PASS (5 isolated cases)\n'
