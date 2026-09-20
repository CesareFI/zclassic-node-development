#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Directory-size observer regression and benchmark; private fixtures only.
# Usage: bash tools/scripts/evidence_dir_bytes_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C
bench=0
case "${1:-}" in
    --bench) bench=1; shift ;;
    --selftest) shift ;;
esac
script_dir="$(cd "$(dirname "$0")" && pwd)"
library="${1:-$script_dir/lib/evidence_sources.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-evidence-dir.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
unset ZCL_EVIDENCE_SOURCES_SH_LOADED
# shellcheck source=tools/scripts/lib/evidence_sources.sh
. "$library"
mkdir "$fixture/data dir"
failures=0

# Keep the real timeout process and argument handling, substitute only du.
mkdir "$fixture/bin"
cat > "$fixture/bin/du" <<'STUB'
#!/usr/bin/env bash
test "$#" -eq 3 && test "$1" = -sb && test "$2" = -- &&
    test "$3" = "$TEST_DIRECTORY" || exit 99
printf '%s' "$TEST_DU_OUTPUT"
if [ "$TEST_DU_STATUS" = hang ]; then exec sleep 5; fi
exit "$TEST_DU_STATUS"
STUB
chmod +x "$fixture/bin/du"
export TEST_DIRECTORY="$fixture/data dir"

check() {
    local label="$1" expected="$4" actual rc=0
    actual="$(PATH="$fixture/bin:$PATH" TEST_DU_OUTPUT="$2" TEST_DU_STATUS="$3" \
        evidence_dir_bytes "$TEST_DIRECTORY" 2> "$fixture/stderr")" || rc=$?
    if [ "$actual" != "$expected" ] || [ "$rc" -ne 0 ] || [ -s "$fixture/stderr" ]; then
        printf 'FAIL: %s expected=<%s> actual=<%s> rc=%s\n' "$label" "$expected" "$actual" "$rc" >&2
        failures=$((failures + 1))
    fi
}

check ordinary $'123456\tfixture\n' 0 123456
check zero $'0\tfixture\n' 0 0
check wide $'18446744073709551615\tfixture\n' 0 18446744073709551615
check whitespace $' \t42  fixture\n' 0 42
check filename-newline $'42\tfixture\nsecond-line\n' 0 42
check first-line-empty $'\n42\tfixture\n' 0 ''
check malformed $'no-size\tfixture\n' 0 ''
check negative $'-1\tfixture\n' 0 ''
check decimal $'1.5\tfixture\n' 0 ''
check empty '' 0 ''
check partial-failure $'123456\tfixture\n' 1 ''
check timed-out-prefix $'123456\tfixture\n' 124 ''
check tool-unavailable '' 127 ''
ZCL_EVIDENCE_TIMEOUT_SEC=0.05 check real-timeout $'123456\tfixture\n' hang ''
( IFS=:; check caller-ifs $'42\tfixture\n' 0 42; test "$failures" -eq 0 ) || failures=$((failures + 1))
( set +o pipefail; check no-pipefail $'123456\tfixture\n' 1 ''; test "$failures" -eq 0 ) || failures=$((failures + 1))

for directory in '' "$fixture/missing" "$fixture/bin/du"; do
    test -z "$(evidence_dir_bytes "$directory")"
done
test -z "$(PATH=/nonexistent evidence_dir_bytes "$TEST_DIRECTORY")"

# Check a real bounded traversal, including a filename with spaces.
printf 'fixture bytes\n' > "$TEST_DIRECTORY/block fixture"
expected="$(du -sb -- "$TEST_DIRECTORY")"
expected=${expected%%$'\t'*}
test "$(evidence_dir_bytes "$TEST_DIRECTORY")" = "$expected"

# Deterministic work budget: no text-parser process per sample.
: > "$fixture/parsers"
(
    awk() { printf 'awk\n' >> "$fixture/parsers"; command awk "$@"; }
    test "$(evidence_dir_bytes "$TEST_DIRECTORY")" = "$expected"
)
parsers="$(wc -l < "$fixture/parsers")"
printf 'external parsers per size observation: %s\n' "$parsers"
if [ "$parsers" -ne 0 ]; then failures=$((failures + 1)); fi

if [ "$bench" = 1 ]; then
    echo 'benchmark: 500 real directory reads, one small file, warm caches'
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time (
        for ((i=0; i<500; i++)); do
            test "$(evidence_dir_bytes "$TEST_DIRECTORY")" = "$expected"
        done
    )
fi
test "$failures" -eq 0
echo 'selftest: PASS directory-size observer'
