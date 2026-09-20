#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Isolated JSON observer regression; --bench also measures synthetic RPC reads.
set -euo pipefail
ulimit -c 0
root=$(cd "$(dirname "$0")/../.." && pwd)
source_file=${JSONQ_SOURCE:-$root/tools/jsonq.c}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/jsonq-key-decode.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
case ${1:-} in ''|--bench) ;; *) echo 'usage: jsonq_key_decode_selftest.sh [--bench]' >&2; exit 2 ;; esac
read -r -a extra_flags <<< "${CFLAGS:--O2}"
compile() {
    "${CC:-cc}" -std=c23 -Wall -Wextra -Werror -pedantic \
        -D_POSIX_C_SOURCE=200809L "${extra_flags[@]}" \
        -I"$root/contexts/commons/packages/zjsonp/include" \
        -I"$root/contexts/commons/packages/zutf8/include" "$@" \
        "$root/contexts/commons/packages/zjsonp/src/zjsonp.c" \
        "$root/contexts/commons/packages/zutf8/src/zutf8.c"
}
compile "$source_file" -o "$tmp/jsonq"
expect() {
    local input=$1 want_status=$2 want=$3 status=0
    shift 3
    printf '%s' "$input" | "$tmp/jsonq" "$@" > "$tmp/out" 2> "$tmp/err" || status=$?
    printf '%s' "$want" > "$tmp/want"
    if [[ $status != "$want_status" ]] || ! cmp -s "$tmp/out" "$tmp/want"; then
        printf 'jsonq key decode: FAIL (%s, status %s expected %s)\n' "$*" "$status" "$want_status" >&2
        cat "$tmp/err" >&2
        exit 1
    fi
}
expect '{"result":{"blocks":123456},"error":null}' 0 $'{"blocks":123456}\n' raw result
expect '{"result":{"blocks":123456},"error":null}' 0 $'null\n' raw error
expect '{"result":{"blocks":123456}}' 0 $'123456\n' get result.blocks
expect '{"r\\esult":1,"result":2}' 0 $'1\n' get 'r\esult'
expect '{"res\u0075lt":[1,2]}' 0 $'2\n' get 'result[1]'
expect '{"result":1,"result":2}' 0 $'1\n' get result
expect '{"result":1}' 1 '' has absent
expect '{"result":1}' 0 '' eq result 1
expect '{"result":[1,{"a":2}]}' 0 $'2\n' count result
expect '{"result":{}}' 0 $'object\n' type result
expect '{"result":1,"error":null}' 0 $'1\n' unwrap
expect '{"result":1,"error":{"code":-1}}' 2 '' unwrap
expect '{"a":1,"b":2}' 0 $'a\nb\n' keys .
# The entire input must remain valid even when the desired key appears first.
expect '{"result":1} garbage' 2 '' raw result
expect '{"result":1,"bad":"\q"}' 2 '' raw result
expect $'{"result":1,"bad":"\377"}' 2 '' raw result
expect '{"result":1,"bad":' 2 '' raw result
expect '{"res\uD800lt":1}' 2 '' raw result
echo 'jsonq key decode: CLI fixtures PASS'

# Compare exact bytes and capacity behavior with the existing decoder. Count
# decoder calls as a deterministic work budget, independent of host speed.
cp "$source_file" "$tmp/jsonq_source.c"
cat > "$tmp/key_test.c" <<'C'
#include "zjsonp/zjsonp.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static unsigned decode_calls;
static size_t observed_decode(const char *text, const zjsonp_event *ev,
                              char *out, size_t cap)
{
    decode_calls++;
    return zjsonp_str_decode(text, ev, out, cap);
}
#define zjsonp_str_decode observed_decode
#define main jsonq_cli_main
#include "jsonq_source.c"
#undef main
#undef zjsonp_str_decode

static void check_key(const char *key, bool plain)
{
    zjsonp_event ev = {.kind = ZJRP_KEY, .off = 0, .len = strlen(key)};
    for (size_t cap = 0; cap <= 258; cap++) {
        char expected[260] = {0}, actual[260] = {0};
        size_t want = zjsonp_str_decode(key, &ev, expected, cap);
        size_t got = SIZE_MAX;
        bool valid = want != SIZE_MAX && want < cap;
        decode_calls = 0;
        bool ok = decode_key(key, &ev, actual, cap, &got);
        assert(ok == valid);
        if (valid) {
            assert(got == want);
            assert(memcmp(actual, expected, got) == 0);
            assert(actual[got] == '\0');
        }
        assert(decode_calls == (plain ? 0u : 1u));
    }
}
int main(void)
{
    char key[258];
    for (size_t len = 0; len <= 257; len++) {
        memset(key, 'a', len);
        key[len] = '\0';
        check_key(key, true);
    }
    for (unsigned c = 32; c < 127; c++) {
        if (c == '"' || c == '\\')
            continue;
        key[0] = (char)c;
        key[1] = '\0';
        check_key(key, true);
    }
    char escaped[601];
    for (size_t i = 0; i < 100; i++)
        memcpy(escaped + i * 6, "\\u0061", 6);
    escaped[600] = '\0';
    check_key(escaped, false); /* encoded length exceeds decoded capacity */
    check_key("res\\u0075lt", false);
    check_key("escaped\\\\key", false);
    check_key("a\\\"b", false);
    check_key("a\\u0000b", false);
    check_key("\\uD83D\\uDE00", false);
    check_key("\\uD800", false);
    check_key("caf\xc3\xa9", false);
    check_key("mixed\xc3\xa9\\n", false);
    puts("jsonq key decode: byte/capacity parity and work budget PASS");
    return 0;
}
C
compile "$tmp/key_test.c" -o "$tmp/key_test"
"$tmp/key_test"
if [[ ${1:-} == --bench ]]; then
    for width in 8 180; do
        awk -v width="$width" 'BEGIN {
            printf "{"
            for (i=0; i<20000; i++) printf "\"diagnostic_%0*d\":0,", width, i
            print "\"result\":{\"blocks\":123456},\"error\":null}"
        }' > "$tmp/wide.json"
        printf 'synthetic RPC: bytes=%s, 100 raw result queries\n' "$(wc -c < "$tmp/wide.json")"
        /usr/bin/time -f 'wall=%e user=%U sys=%S maxrss_kib=%M' \
            bash -c 'for ((i=0;i<100;i++)); do "$1" raw result < "$2" > /dev/null || exit; done' \
            _ "$tmp/jsonq" "$tmp/wide.json"
    done
fi
