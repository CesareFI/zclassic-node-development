#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise extracted readers only: never launch the fresh-boot node harness.
# Usage: bash tools/scripts/fresh_boot_fields_selftest.sh [--bench] [SCRIPT]
set -euo pipefail
export LC_ALL=C
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script=${1:-$script_dir/fresh-boot-proof.sh}
[ "$#" -le 1 ] || { echo 'fresh-boot-fields: too many arguments' >&2; exit 2; }
work="$(mktemp -d "${TMPDIR:-/tmp}/zcl-fresh-boot-fields.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
sed -n '/^jget() {/,/^}/p; /^jget_header_admit() {/,/^}/p' "$script" > "$work/readers.sh"
. "$work/readers.sh"
declare -F jget >/dev/null
declare -F jget_header_admit >/dev/null
checks=0
check() {
    local label=$1 expected=$2 want_rc=$3 actual rc=0
    shift 3
    actual=$("$@") || rc=$?
    if [ "$actual" != "$expected" ] || [ "$rc" -ne "$want_rc" ]; then
        printf 'fresh-boot-fields: FAIL %s: got <%s> rc=%s; want <%s> rc=%s\n' \
            "$label" "$actual" "$rc" "$expected" "$want_rc" >&2
        exit 1
    fi
    checks=$((checks + 1))
}

check compact 123 0 jget '{"hstar":123,"network_tip":456}' hstar
check spaced -1 0 jget $'{ "hstar" \t: \r-1 }' hstar
check genesis 0 0 jget '{"hstar":0}' hstar
check leading-zeros 0007 0 jget '{"hstar":0007}' hstar
check wide 18446744073709551615 0 jget '{"hstar":18446744073709551615}' hstar
check duplicate 12 0 jget '{"hstar":12,"hstar":34}' hstar
check later-line 34 0 jget $'{"hstar":null}\n{"hstar":34}' hstar
check first-line 12 0 jget $'{"hstar":12}\n{"hstar":34}' hstar
check no-cross-line '' 1 jget $'{"hstar"\n:34}' hstar
check skip-cross-line 56 0 jget $'{"hstar":\n34}\n{"hstar":56}' hstar
# Preserve existing integer-prefix behavior; these are field readers, not
# JSON validity or consensus checks.
check integer-prefix 12 0 jget '{"hstar":12.5}' hstar
check escaped-content 78 0 jget '{"note":"\\","hstar":78}' hstar
check missing '' 1 jget '{"cached_provable_tip":12}' hstar
check null '' 1 jget '{"hstar":null}' hstar
check quoted '' 1 jget '{"hstar":"12"}' hstar
check empty '' 1 jget '' hstar
check count 2 0 jget '{"active_count":2}' active_count

check stage 42 0 jget_header_admit '{"stage":"header_admit","cursor":42}'
check stage-spaced -1 0 jget_header_admit $'{"stage" : "header_admit",\n "cursor" : -1}'
check stage-wide 9007199254740993 0 jget_header_admit '{"stage":"header_admit","cursor":9007199254740993}'
check stage-zero 0 0 jget_header_admit '{"stage":"header_admit","cursor":0}'
check stage-leading-zeros 0007 0 jget_header_admit '{"stage":"header_admit","cursor":0007}'
check other-stage 42 0 jget_header_admit '[{"stage":"body_fetch","cursor":99},{"stage":"header_admit","cursor":42}]'
check stage-first 42 0 jget_header_admit '[{"stage":"header_admit","cursor":42},{"stage":"header_admit","cursor":99}]'
check stage-greedy-cursor 99 0 jget_header_admit '{"stage":"header_admit","cursor":42,"cursor":99}'
check stage-no-cross-object '' 1 jget_header_admit '[{"stage":"header_admit"},{"cursor":42}]'
check stage-wrong '' 1 jget_header_admit '{"stage":"body_fetch","cursor":42}'
check stage-null '' 1 jget_header_admit '{"stage":"header_admit","cursor":null}'
check stage-empty '' 1 jget_header_admit ''

frontier='{"hstar":123,"network_tip":456,"stages":[{"stage":"header_admit","cursor":450},{"stage":"body_fetch","cursor":122}]}'
blocker='{"active_count":2,"blockers":[]}'
sample() {
    check sample-stage 450 0 jget_header_admit "$frontier"
    check sample-height 123 0 jget "$frontier" hstar
    check sample-tip 456 0 jget "$frontier" network_tip
    check sample-blockers 2 0 jget "$blocker" active_count
}
sample
printf 'fresh-boot-fields: PASS (%s value/status checks)\n' "$checks"

if [ "$bench" -eq 1 ]; then
    printf 'fresh-boot-fields: benchmark samples=500 fields/sample=4 bytes/sample=%s\n' \
        "$((${#frontier} + ${#blocker}))"
    TIMEFORMAT='fresh-boot-fields: wall=%3R user=%3U sys=%3S'
    time for ((i=0; i<500; i++)); do sample; done
fi

# Count actual external parsers, not a noisy wall-time ceiling. Wrappers run
# only after timing; the original baseline must fail this budget.
grep() { printf 'grep\n' >> "$work/parsers"; command grep "$@"; }
head() { printf 'head\n' >> "$work/parsers"; command head "$@"; }
tr() { printf 'tr\n' >> "$work/parsers"; command tr "$@"; }
: > "$work/parsers"
sample
count=$(wc -l < "$work/parsers")
printf 'fresh-boot-fields: parser processes/sample=%s (required 0)\n' "$count"
[ "$count" -eq 0 ]
