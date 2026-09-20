#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Boolean evidence polling: exact bytes/status and bounded observer work.
# Usage: bash tools/scripts/evidence_bool_poll_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
if [[ ${1:-} == --selftest ]]; then shift; fi
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
library=${1:-$root/tools/scripts/lib/evidence_sources.sh}
fixture=$(mktemp -d /tmp/z23-bool-poll.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
unset ZCL_EVIDENCE_SOURCES_SH_LOADED
# shellcheck source=tools/scripts/lib/evidence_sources.sh
. "$library"

check() {
    local input=$1 expected=$2 label=$3
    evidence_json_bool "$input" ready > "$fixture/actual"
    printf '%s' "$expected" > "$fixture/expected"
    if ! cmp -s "$fixture/expected" "$fixture/actual"; then
        printf 'FAIL: %s\n' "$label" >&2
        exit 1
    fi
}
check '' '' empty
check '{}' '' absent
check '{"ready":true}' $'true\n' true
check '{"ready":false}' $'false\n' false
check $'{"ready"\t\r\v\f : false}' $'false\n' whitespace
check '{"already":true,"ready_suffix":false}' '' exact-key
check '{"ready":"true","ready":null}' '' non-boolean
check '{"ready":true_suffix}' $'true\n' existing-prefix-policy
check '{"ready":true,"ready":false}' $'false\n' last-match
check '{"ready":false,"ready":true}' $'true\n' last-match-reverse
check '{"ready":true,"ready":null}' $'true\n' last-valid-match
check $'{"ready":false}\n{"ready":true}' $'false\n' first-matching-line
check $'no match\n{"ready":true,"ready":false}' $'false\n' late-line
check $'{"ready":\ntrue}' '' no-cross-line-match
check $'{"ready"\n:true}' '' no-cross-line-key
printf -v padding '%8192s' ''
check "${padding}{\"ready\":false}" $'false\n' long-line
for length in 4081 4082; do
    printf -v padding '%*s' "$length" ''
    check "${padding}{\"ready\":false}" $'false\n' fast-path-boundary
done
many=$'{"ready":true}\n'
for ((i=0; i<15; i++)); do many+="$many"; done
check "$many" $'true\n' large-repeated-input
check "${many//ready/other}" '' large-missing-input
printf 'PASS: boolean values, bytes, duplicates, line boundaries and large input\n'

# Function wrappers measure external tool use without ptrace or timing gates.
: > "$fixture/calls"
sed() { printf 'sed\n' >> "$fixture/calls"; command sed "$@"; }
doc='{"height":3200000,"stage":"header_admit","ready":false}'
for ((i=0; i<100; i++)); do evidence_json_bool "$doc" ready > /dev/null; done
calls=$(wc -l < "$fixture/calls")
printf '100 compact boolean observations: external_tools=%s\n' "$calls"
: > "$fixture/calls"
printf -v padding '%4081s' ''
evidence_json_bool "${padding}{\"ready\":false}" ready > /dev/null
evidence_json_bool " ${padding}{\"ready\":false}" ready > /dev/null
evidence_json_bool $'{"ready":false}\n{"ready":true}' ready > /dev/null
fallback_calls=$(wc -l < "$fixture/calls")
unset -f sed
if (( bench )); then
    TIMEFORMAT='2000 compact observations: %3R s wall, %3U s user, %3S s system'
    for ((run=0; run<3; run++)); do
        time for ((i=0; i<2000; i++)); do
            evidence_json_bool "$doc" ready > /dev/null
        done
    done
fi
if (( calls != 0 )); then
    echo 'FAIL: compact boolean polling still starts external tools' >&2
    exit 1
fi
if (( fallback_calls != 2 )); then
    echo 'FAIL: large/multiline parser fallback boundary changed' >&2
    exit 1
fi
printf 'selftest: PASS compact boolean polling process budget\n'
