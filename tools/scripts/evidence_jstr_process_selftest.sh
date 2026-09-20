#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Byte equivalence and shell-process budget for sync evidence string emission.
# Usage: bash tools/scripts/evidence_jstr_process_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C
bench=0
case "${1:-}" in
    --bench) bench=1; shift ;;
    --selftest) shift ;;
esac
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
library="${1:-$script_dir/lib/evidence_sources.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-evidence-jstr.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
unset ZCL_EVIDENCE_SOURCES_SH_LOADED
# shellcheck source=tools/scripts/lib/evidence_sources.sh
. "$library"

# Compare complete literals against the previous wrapper, including bytes that
# command substitution might otherwise trim. NUL cannot be a shell argument.
bytes=''
for ((i=1; i<=255; i++)); do
    printf -v octal '%03o' "$i"
    printf -v byte '%b' "\\$octal"
    bytes+="$byte"
done
for input in '' 'waiting_for_headers' $'"quoted"\\path\n\r\t' \
             $'trailing\n\n' 'café → tip' "$bytes" "$bytes$bytes"; do
    printf '"%s"' "$(evidence_json_escape "$input")" > "$fixture/expected"
    evidence_jstr "$input" > "$fixture/actual"
    cmp "$fixture/expected" "$fixture/actual"
done
evidence_jstr > "$fixture/actual"
printf '""' > "$fixture/expected"
cmp "$fixture/expected" "$fixture/actual"
echo 'complete string literals: byte-identical (including omitted argument)'

if [ "$bench" = 1 ]; then
    bench_input=$'waiting_for_headers\n"fixture"\\path\t123456'
    printf 'benchmark: 500 literals, %s-byte input, warm host caches\n' "${#bench_input}"
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    time (
        for ((i=0; i<500; i++)); do
            evidence_jstr "$bench_input" > /dev/null
        done
    )
fi

# An instrumented escape helper must execute in the calling shell. File output
# avoids introducing a command substitution in the test itself. This catches
# a nested shell even when it runs only builtins and no external text tools.
evidence_json_escape() { printf '%s' "$BASHPID"; }
printf '"%s"' "$BASHPID" > "$fixture/expected"
evidence_jstr 'process-budget' > "$fixture/actual"
if ! cmp -s "$fixture/expected" "$fixture/actual"; then
    echo 'selftest: FAIL string wrapper starts a child shell' >&2
    exit 1
fi
echo 'selftest: PASS evidence string wrapper uses the calling shell'
