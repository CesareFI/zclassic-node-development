#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise anchor-copy preflight with an inert mint stub and private fixtures.
# Usage: bash tools/scripts/anchor_resume_preflight_selftest.sh [--bench] [producer]
set -euo pipefail
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
producer=${1:-$script_dir/produce_anchor_snapshot.sh}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-anchor-resume.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'anchor resume preflight: FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "$fixture/bin" "$fixture/source" "$fixture/work"
printf 'source fixture\n' > "$fixture/source/marker"
printf 'durable progress fixture\n' > "$fixture/work/progress"
export ANCHOR_TEST_TRACE="$fixture/trace"
export ANCHOR_TEST_DU
ANCHOR_TEST_DU=$(command -v du)
export ANCHOR_TEST_AVAILABLE=1000000000 ANCHOR_TEST_SIZE=100
cat > "$fixture/bin/df" <<'STUB'
#!/usr/bin/env bash
printf 'df\n' >> "$ANCHOR_TEST_TRACE"
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\n'
printf 'fixture 1000000000 0 %s 0%% /\n' "$ANCHOR_TEST_AVAILABLE"
STUB
cat > "$fixture/bin/du" <<'STUB'
#!/usr/bin/env bash
printf 'du\n' >> "$ANCHOR_TEST_TRACE"
if [ "${ANCHOR_TEST_REAL_DU:-0}" = 1 ]; then
    exec "$ANCHOR_TEST_DU" "$@"
fi
printf '%s\tfixture\n' "$ANCHOR_TEST_SIZE"
STUB
cat > "$fixture/bin/node" <<'STUB'
#!/usr/bin/env bash
printf 'mint\n' >> "$ANCHOR_TEST_TRACE"
if [ "${ANCHOR_TEST_SNAPSHOT:-0}" = 1 ]; then
    printf 'unverified fixture\n' > "${1#-datadir=}/utxo-anchor.snapshot"
fi
# Stop before any snapshot verification; this is never evidence of a mint.
exit "${ANCHOR_TEST_MINT_RC:-23}"
STUB
chmod +x "$fixture/bin/df" "$fixture/bin/du" "$fixture/bin/node"
run_producer() {
    : > "$ANCHOR_TEST_TRACE"
    local rc=0
    PATH="$fixture/bin:$PATH" \
    ZCL_PAS_BINARY="$fixture/bin/node" \
    ZCL_PAS_SOURCE_DATADIR="$fixture/source" \
    ZCL_PAS_WORK_DATADIR="$fixture/work" \
    ZCL_PAS_VERIFY_DATADIR="$fixture/verify" \
    ZCL_PAS_VERDICT_LOG="$fixture/verdict" \
    ZCL_PAS_OPERATOR_LANE=test \
    ZCL_PAS_MINT_FLAGS=-mint-anchor \
        bash "$producer" > "$fixture/output" 2>&1 || rc=$?
    [ "$rc" = 1 ] || fail "expected preflight/mint refusal, got $rc"
    grep -q '^VERDICT: FAIL$' "$fixture/verdict" || fail 'missing failure verdict'
}
expect_trace() {
    local actual
    actual=$(cat "$ANCHOR_TEST_TRACE")
    [ "$actual" = "$1" ] || fail "expected calls [$1], got [$actual]"
}

if [ "$bench" = 1 ]; then
    # Real recursive metadata cost on a warm, synthetic source tree. No block
    # bytes, network, production state or actual mint process participates.
    for ((d = 0; d < 100; d++)); do
        mkdir "$fixture/source/dir$d"
        for ((f = 0; f < 200; f++)); do
            : > "$fixture/source/dir$d/file$f"
        done
    done
    export ANCHOR_TEST_REAL_DU=1
    printf 'anchor resume benchmark: 20 resumes, 20000 empty source files\n'
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time for ((sample = 0; sample < 20; sample++)); do run_producer; done
    unset ANCHOR_TEST_REAL_DU
fi

# Existing work must reach the mint without enumerating the source tree.
run_producer
expect_trace mint
grep -q 'mint-anchor exited non-zero (23)' "$fixture/verdict" || fail 'mint refusal lost'
[ "$(cat "$fixture/work/progress")" = 'durable progress fixture' ] || fail 'resume modified progress'
[ ! -e "$fixture/work/marker" ] || fail 'resume recopied source'

# The copy-space estimate is irrelevant to a resume, even on a full fixture.
ANCHOR_TEST_AVAILABLE=0 run_producer
expect_trace mint

# New copies retain the exact doubled-source-size admission threshold.
rm -rf -- "$fixture/work"
ANCHOR_TEST_AVAILABLE=199 run_producer
expect_trace $'df\ndu'
grep -q 'insufficient disk: need ~200KB' "$fixture/verdict" || fail 'copy-space refusal lost'
[ ! -e "$fixture/work" ] || fail 'refused copy created work directory'
ANCHOR_TEST_AVAILABLE=200 run_producer
expect_trace $'df\ndu\nmint'
cmp "$fixture/source/marker" "$fixture/work/marker" || fail 'copy bytes differ'

# Resume still requires an available source and an executable producer.
mv "$fixture/source" "$fixture/source.saved"
run_producer
expect_trace ''
grep -q 'source datadir missing' "$fixture/verdict" || fail 'source precondition lost'
mv "$fixture/source.saved" "$fixture/source"
chmod -x "$fixture/bin/node"
run_producer
expect_trace ''
grep -q 'binary not executable' "$fixture/verdict" || fail 'binary precondition lost'
chmod +x "$fixture/bin/node"

# Removing the copy preflight cannot admit an unverified snapshot on resume.
ANCHOR_TEST_MINT_RC=0 run_producer
expect_trace mint
grep -q 'is missing/empty' "$fixture/verdict" || fail 'snapshot presence check lost'
ANCHOR_TEST_MINT_RC=0 ANCHOR_TEST_SNAPSHOT=1 run_producer
expect_trace mint
grep -q 'internal hard-verify SUCCESS line is absent' "$fixture/verdict" || fail 'verification check lost'
printf 'anchor resume preflight: PASS (8 scenarios)\n'
