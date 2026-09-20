#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Test only the fresh-boot log reader; never run the destructive boot harness.
# Optional --bench times a generated log; optional PATH selects an old reader.
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bench=0
if [ "${1:-}" = --bench ]; then bench=1; shift; fi
script="${1:-$SCRIPT_DIR/fresh-boot-proof.sh}"
[ "$#" -le 1 ] || { echo 'usage: fresh_boot_log_max_selftest.sh [--bench] [PATH]' >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zcl-boot-log-max.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT
sed -n '/^log_max() {/,/^}/p' "$script" > "$tmp/reader.sh"
. "$tmp/reader.sh"
declare -F log_max >/dev/null
NODE_LOG="$tmp/node.log"
checks=0
check() {
    local got
    # The boot harness treats unavailable log progress as an empty read.
    got="$(log_max "$2")" || true
    [ "$got" = "$3" ] || {
        printf 'boot-log-max: FAIL %s: got <%s>, expected <%s>\n' "$1" "$got" "$3" >&2
        exit 1
    }
    checks=$((checks + 1))
}
check missing-file 'header tip' ''
: > "$NODE_LOG"
check empty 'header tip' ''
printf '%s\n' 'unrelated 9999999' 'header tip=-1' 'header tip=unknown' > "$NODE_LOG"
check missing-height 'header tip' ''
printf '%s\n' '(header tip=0, chain tip=0)' >> "$NODE_LOG"
check genesis 'header tip' 0
printf '%s\n' '(header tip=42, chain tip=12)' '(header tip=9, chain tip=7)' >> "$NODE_LOG"
check numeric-order 'header tip' 42
check independent-chain 'chain tip' 12
printf '%s\n' 'header tip=13 header tip=3200000 header tip=14' >> "$NODE_LOG"
check same-line 'header tip' 3200000
printf '%s\n' 'header tip=3200000' 'header tip=2' >> "$NODE_LOG"
check duplicate-and-regression 'header tip' 3200000
printf '%s\n' 'header tip=00042 header tip=0009' > "$NODE_LOG"
check leading-zero-text 'header tip' 00042
printf '%s\n' 'header tip=0042 header tip=042' >> "$NODE_LOG"
check numeric-tie 'header tip' 042
printf '%s\n' 'header tip=18446744073709551615 header tip=18446744073709551614' > "$NODE_LOG"
check wide-exact 'header tip' 18446744073709551615
printf '%s\n' 'header tip=018446744073709551614 header tip=0018446744073709551615' > "$NODE_LOG"
check wide-rounded-tie 'header tip' 0018446744073709551615
printf '%s\n' 'header tip=18446744073709551615' >> "$NODE_LOG"
check wide-spelling-tie 'header tip' 18446744073709551615
printf '%s\n' 'header tip=000 header tip=00 header tip=0' > "$NODE_LOG"
check zero-spelling-tie 'header tip' 000
printf '%s' 'header tip=5.2 chain tip=7suffix' > "$NODE_LOG"
check integer-prefix 'header tip' 5
check unterminated-line 'chain tip' 7
printf '%s\n' 'header tip=2' > "$NODE_LOG"
check truncation 'header tip' 2
printf '%s\n' 'header tip=8' > "$tmp/replacement"
mv "$tmp/replacement" "$NODE_LOG"
check replacement 'header tip' 8
printf 'boot-log-max: PASS (%s behavior checks)\n' "$checks"

if [ "$bench" -eq 1 ]; then
    # Descending repeated heights model a large warm log without a live node.
    awk 'BEGIN { for (i=200000; i>0; i--) printf "peer batch (header tip=%d, chain tip=%d)\n", i, i/2 }' > "$NODE_LOG"
    printf 'boot-log-max: benchmark bytes=%s samples=10 (two reads/sample)\n' "$(wc -c < "$NODE_LOG")"
    TIMEFORMAT='boot-log-max: wall=%3R user=%3U sys=%3S'
    time for ((i=0; i<10; i++)); do
        check bench-header 'header tip' 200000
        check bench-chain 'chain tip' 100000
    done
fi

# The deterministic regression gate is process count, not noisy wall time.
grep() { printf 'grep\n' >> "$tmp/parsers"; command grep "$@"; }
sort() { printf 'sort\n' >> "$tmp/parsers"; command sort "$@"; }
tail() { printf 'tail\n' >> "$tmp/parsers"; command tail "$@"; }
awk() { printf 'awk\n' >> "$tmp/parsers"; command awk "$@"; }
: > "$tmp/parsers"
printf '%s\n' 'header tip=8 chain tip=7' > "$NODE_LOG"
log_max 'header tip' >/dev/null
log_max 'chain tip' >/dev/null
count="$(wc -l < "$tmp/parsers")"
printf 'boot-log-max: parser processes/sample=%s (required 4)\n' "$count"
[ "$count" -eq 4 ]
