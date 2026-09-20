#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Usage: bash tools/scripts/stopwatch_quote_selftest.sh [--bench] [library]
set -euo pipefail
export LC_ALL=C

bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
library="${1:-$script_dir/stopwatch_json_lib.sh}"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/zcl-stopwatch-quote.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# shellcheck source=tools/scripts/stopwatch_json_lib.sh
. "$library"

# Compare bytes, including trailing spaces, with the original streaming oracle.
bytes=''
for ((i=1; i<=255; i++)); do
    printf -v octal '%03o' "$i"
    printf -v byte '%b' "\\$octal"
    bytes+="$byte"
done
for input in '' 'waiting_for_headers' $'\\"\n\r\t%s' $'\n\n' \
             'café → tip' "$bytes" "$bytes$bytes$bytes$bytes"; do
    {
        printf '"'
        printf '%s' "$input" |
            sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g' |
            tr '\n' ' '
        printf '"'
    } > "$fixture/expected"
    json_string "$input" > "$fixture/actual"
    cmp "$fixture/expected" "$fixture/actual"
done
echo 'quote bytes: PASS (including every non-NUL byte and trailing whitespace)'

if (( bench )); then
    input=$'waiting_for_headers\n"fixture"\\path\t123456'
    printf 'benchmark: 500 captured quotes, %s bytes, three warm-cache trials\n' "${#input}"
    TIMEFORMAT='wall=%3R user=%3U sys=%3S seconds'
    for ((trial=0; trial<3; trial++)); do
        time (
            for ((i=0; i<500; i++)); do
                value="$(json_string "$input")"
                [[ -n $value ]]
            done
        )
    done
fi

# Instrument the call boundary: escaping must run in the wrapper's process.
# Unlike a timing threshold, this detects a nested substitution on any host.
(
    caller_pid=$BASHPID
    json_escape() {
        printf '%s\n' "$BASHPID" > "$fixture/escape-pid"
        printf '%s' "$1"
    }
    json_string probe > "$fixture/actual"
    printf '"probe"' > "$fixture/expected"
    cmp "$fixture/expected" "$fixture/actual"
    IFS= read -r escape_pid < "$fixture/escape-pid"
    if [[ $escape_pid != "$caller_pid" ]]; then
        echo 'FAIL: json_string starts a nested shell for escaping' >&2
        exit 1
    fi
)
echo 'selftest: PASS stopwatch quoting adds no shell process'
