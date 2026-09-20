#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic blocker observation regression and process-cost benchmark.
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
fixture=$(mktemp -d /tmp/z23-blocker-ids.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
sed -n '/^blocker_ids() {/,/^}/p' "$subject" > "$fixture/reader.sh"
. "$fixture/reader.sh"
declare -F blocker_ids >/dev/null || { echo 'missing blocker reader' >&2; exit 1; }
check() {
    local actual expected
    # Retain the trailing newline and the no-match status, not just ID text.
    actual=$(if blocker_ids "$2"; then printf '@0'; else printf '@%s' "$?"; fi)
    expected="$1"$'\n@'"${3:-0}"
    [[ $actual == "$expected" ]] || {
        printf 'FAIL blocker IDs: expected <%s>, got <%s>\n' "$expected" "$actual" >&2
        exit 1
    }
}
doc='{"active_count":2,"blockers":[{"id":"headers.wait","age":2},{"id":"body.persist"}]}'
check 'headers.wait,body.persist' "$doc"
check '' '' 1
check '' '{}' 1
check '' '{"id":null,"peer_id":"other","ids":"other"}' 1
check '' '{"id":17}' 1
check '' '{"id":""}'
check ',a,' '{"id":""},{"id":"a"},{"id":""}'
check 'a,a,b' '{"id":"a","id":"a"},{"id":"b"}'
check 'a,b' $'{"id" \t\r\v\f: \t"a"},\n{"id":"b"}'
check 'ab' $'{"i\nd"\n:\n"a\nb"}'
check 'a,b' '{"id":"a,b"}'
check 'a\b' '{"id":"a\b"}'
check 'a\' '{"id":"a\"b"}'
check 'a:b' '{"id":"a:b"}'
check $'a\tb\rc' $'{"id":"a\tb\rc"}'
check 'a' '{"id":"a"},{"id":null}'
# Preserve the compact native reader policy; this is not a general JSON parser.
printf -v padding '%131072s' ''
check 'headers.wait,body.persist' "$doc$padding"
check 'headers.wait,body.persist' "$padding$doc"
many=''; expected=''
for ((i=0;i<256;i++)); do
    many+="{\"id\":\"stage.$i\"},"
    expected+="${expected:+,}stage.$i"
done
check "$expected" "$many"
printf 'blocker ID values and statuses: PASS\n'

observe_tool() {
    local tool=$1
    shift
    printf '%s\n' "$tool" >> "$fixture/calls"
    command "$tool" "$@"
}
awk() { observe_tool awk "$@"; }
tr() { observe_tool tr "$@"; }
grep() { observe_tool grep "$@"; }
sed() { observe_tool sed "$@"; }
paste() { observe_tool paste "$@"; }
: > "$fixture/calls"
check 'headers.wait,body.persist' "$doc"
calls=$(wc -l < "$fixture/calls")
printf 'blocker IDs per poll: external_tools=%s\n' "$calls"
unset -f awk tr grep sed paste
if (( bench )); then
    TIMEFORMAT='500 polls: %3R s wall, %3U s user, %3S s system'
    time for ((i=0;i<500;i++)); do
        blocker_ids "$doc" > /dev/null
    done
fi
[[ $calls == 1 ]] || { echo 'FAIL: expected one external tool per blocker read' >&2; exit 1; }
printf 'blocker ID process budget: PASS\n'
