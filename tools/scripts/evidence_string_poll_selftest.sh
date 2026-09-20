#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Short sync-observer strings: values/status and subprocess budget, offline.
# Usage: bash tools/scripts/evidence_string_poll_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
library=${1:-$root/tools/scripts/lib/evidence_sources.sh}
fixture=$(mktemp -d /tmp/z23-string-poll.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
unset ZCL_EVIDENCE_SOURCES_SH_LOADED
# shellcheck source=tools/scripts/lib/evidence_sources.sh
. "$library"
check() {
    local input=$1 expected=$2 label=$3 key=${4:-stage} actual
    evidence_json_str "$input" "$key" > "$fixture/actual"
    # Collectors consume these fields through command substitution.
    actual=$(< "$fixture/actual")
    if [[ $actual != "${expected%$'\n'}" ]]; then
        printf 'FAIL: %s\n' "$label" >&2
        exit 1
    fi
}
check '' '' empty
check '{}' '' absent
check '{"stage":null}' '' null
check '{"stage":42}' '' number
check '{"other_stage":"x","stage_suffix":"y"}' '' exact-key
check '{"stage":""}' $'\n' empty-string
check '{"stage":"header_admit"}' $'header_admit\n' stage
check $'{"stage"\t\r\v\f : "waiting for headers"}' $'waiting for headers\n' whitespace
check '{"stage":"a\\b"}' $'a\\\\b\n' literal-backslashes
check '{"stage":"a\"b"}' $'a\\\n' existing-escaped-quote-policy
check '{"stage":"a","stage":"b"}' $'b\n' last-match
check '{"stage":"a","stage":""}' $'\n' last-empty
check '{"stage":"a","stage":null}' $'a\n' last-valid-match
check $'{"stage":"a"}\n{"stage":"b"}' $'a\n' first-line
check $'{"stage":""}\n{"stage":"b"}' $'\n' first-empty-line
check $'missing\n{"stage":"b"}' $'b\n' late-line
check $'{"stage":\n"a"}' '' no-cross-line-value
check $'{"stage":"a\nb"}' '' no-cross-line-string
# Non-identifier keys retain the legacy sed/BRE interpretation.
check '{"stage+":"x"}' $'x\n' literal-plus 'stage+'
check '{"stage":"x"}' $'x\n' legacy-key-pattern 'sta.e'
for length in 4083 4084 8192; do
    printf -v padding '%*s' "$length" ''
    check "${padding}{\"stage\":\"x\"}" $'x\n' size-boundary
done
many=$'{"stage":"headers"}\n'
for ((i=0; i<6; i++)); do many+="$many"; done
check "$many" $'headers\n' repeated-lines
check "${many//stage/other}" '' missing-lines

# Count tools in subprocesses too, without relying on ptrace or wall timing.
: > "$fixture/calls"
sed() { printf 'sed\n' >> "$fixture/calls"; command sed "$@"; }
doc='{"height":3200000,"stage":"header_admit","ready":false}'
for ((i=0; i<100; i++)); do evidence_json_str "$doc" stage > /dev/null; done
calls=$(wc -l < "$fixture/calls")
: > "$fixture/calls"
printf -v padding '%4083s' ''
evidence_json_str "${padding}{\"stage\":\"x\"}" stage > /dev/null
evidence_json_str " ${padding}{\"stage\":\"x\"}" stage > /dev/null
evidence_json_str $'{"stage":"a"}\n{"stage":"b"}' stage > /dev/null
evidence_json_str '{"stage+":"x"}' 'stage+' > /dev/null
fallback_calls=$(wc -l < "$fixture/calls")
unset -f sed
printf '100 compact string observations: external_tools=%s\n' "$calls"
if (( bench )); then
    TIMEFORMAT='2000 compact observations: %3R s wall, %3U s user, %3S s system'
    for ((run=0; run<3; run++)); do
        time for ((i=0; i<2000; i++)); do
            evidence_json_str "$doc" stage > /dev/null
        done
    done
fi
if (( calls != 0 || fallback_calls != 3 )); then
    printf 'FAIL: string observer process budget (compact=%s fallback=%s)\n' \
        "$calls" "$fallback_calls" >&2
    exit 1
fi
echo 'selftest: PASS evidence string polling'
