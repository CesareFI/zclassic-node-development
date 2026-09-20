#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Fixture-only explorer observer regression and scan-cost benchmark; no network.
# Usage: bash public_explorer_observer_selftest.sh [--bench] [smoke-script]
set -euo pipefail
export LC_ALL=C
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
probe="${1:-$script_dir/public_explorer_smoke.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-explorer-observer.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"
export EXPLORER_FIXTURE="$fixture"

# Count actual API-file readers, including unsuccessful marker searches.
# Other library work and the separate HTML observation are outside this budget.
for tool in awk grep sed; do
    real_tool="$(command -v "$tool")"
    cat > "$fixture/bin/$tool" <<EOF
#!/usr/bin/env bash
for arg do
    case "\$arg" in
        */hodl.json)
            printf '%s\\n' '$tool' >> "\$EXPLORER_FIXTURE/readers"
            if [ '$tool' = awk ] && [ "\${EXPLORER_READER_FAIL:-0}" = 1 ]; then
                printf '1|1|1|1|0|42|99.0\\n'
                exit 7
            fi
            ;;
    esac
done
exec '$real_tool' "\$@"
EOF
    chmod +x "$fixture/bin/$tool"
done

good='{"schema":"zcl.hodl_wave.v1","status":"ok","blocker":"none","fresh":true,"served_height":3197857,"older_than_1y":{"value":1.0,"percent":61.5},"skipped_rows":0}'
fetch='case "$URL" in *api*) cp "$EXPLORER_FIXTURE/api" "$OUT";; *) cp "$EXPLORER_FIXTURE/html" "$OUT";; esac; echo 200'
run_probe() {
    env PATH="$fixture/bin:$PATH" \
        ZCL_PUBLIC_BASE=https://example.invalid \
        ZCL_PUBLIC_SMOKE_LEDGER_DIR="$fixture/ledger" \
        ZCL_PUBLIC_SMOKE_FETCH_CMD="$fetch" \
        bash "$probe" > "$fixture/stdout" 2> "$fixture/stderr"
}
checks=0
check() {
    local label="$1" body="$2" page="$3" expected_rc="$4" stage="$5" height="$6" percent="$7" rc=0 line
    printf '%s' "$body" > "$fixture/api"
    printf '%s' "$page" > "$fixture/html"
    run_probe || rc=$?
    line="$(tail -n1 "$fixture/ledger/availability-ledger.jsonl")"
    if [ "$rc" != "$expected_rc" ] ||
       [[ "$line" != *"\"fail_stage\":\"$stage\""* ]] ||
       [[ "$line" != *"\"served_height\":$height,\"older_than_1y_percent\":\"$percent\""* ]]; then
        printf 'selftest: FAIL %s rc=%s ledger=%s\n' "$label" "$rc" "$line" >&2
        exit 1
    fi
    checks=$((checks + 1))
}

: > "$fixture/readers"
check healthy "$good" '<html>ready</html>' 0 '' 3197857 61.5
readers="$(wc -l < "$fixture/readers")"
check schema "${good/zcl.hodl_wave.v1/wrong}" ready 1 api_schema 3197857 61.5
check status "${good/\"ok\"/\"bad\"}" ready 1 api_status 3197857 61.5
check blocker "${good/\"none\"/\"busy\"}" ready 1 api_blocker 3197857 61.5
check stale "${good/true/false}" ready 1 api_stale 3197857 61.5
check late-wait "$good"$'\nPLEASE RETRY' ready 1 api_wait_marker 3197857 61.5
check html-wait "$good" 'Temporarily Unavailable' 1 html_wait_marker 3197857 61.5
check failure-order '{}' 'waiting' 1 api_schema null ''
check duplicate "$good"',"served_height":9007199254740993' ready 0 '' 9007199254740993 61.5
check multiline "$good"$'\n"served_height":42' ready 0 '' 3197857 61.5
check fields-only $'"served_height":11\n"older_than_1y":{"value":0.5,"percent":0.25},"skipped_rows":0' ready 1 api_schema 11 0.25
check duplicate-percent "$good"',"older_than_1y":{"value":1,"percent":99.0},"skipped_rows":0' ready 0 '' 3197857 99.0
check no-height "${good/\"served_height\":3197857,/}" ready 0 '' null 61.5
check no-percent "${good/\"percent\":61.5/\"absent\":61.5}" ready 0 '' 3197857 ''
check formatted "${good/\"fresh\":true/\"fresh\": true}" ready 1 api_stale 3197857 61.5
for marker in 'Refresh In A Minute' 'NOT PROCESSED' 'Try Again' 'Waiting' 'TEMPORARILY UNAVAILABLE'; do
    check wait-marker "$good"$'\n'"$marker" ready 1 api_wait_marker 3197857 61.5
done
printf 'explorer observer: %s evidence cases; API readers per observation=%s\n' "$checks" "$readers"

if [ "$bench" = 1 ]; then
    # Readiness markers at the front, realistic large projection tail, and a
    # final wait marker: scanning must cover the whole response on each run.
    printf '%s\n' "$good" > "$fixture/api"
    awk 'BEGIN { for (i=0; i<8192; i++) print "projection-history-012345678901234567890123456789012345678901234567"; print "PLEASE RETRY" }' >> "$fixture/api"
    printf 'ready' > "$fixture/html"
    printf 'benchmark: 20 complete observations, API bytes=%s, warm filesystem caches\n' "$(wc -c < "$fixture/api")"
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time for ((i=0; i<20; i++)); do
        rc=0
        run_probe || rc=$?
        [ "$rc" = 1 ] || { echo 'selftest: FAIL benchmark wait marker lost' >&2; exit 1; }
    done
fi
if [ "$readers" != 1 ]; then
    echo 'selftest: FAIL expected one API-file reader per observation' >&2
    exit 1
fi
# A reader can emit a plausible prefix before failing. The caller must clear
# all observations on nonzero status and still record a failed check.
export EXPLORER_READER_FAIL=1
check reader-failure "$good" ready 1 api_schema null ''
echo 'selftest: PASS explorer observer'
