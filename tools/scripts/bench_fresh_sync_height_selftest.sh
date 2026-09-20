#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Measure height-RPC demand in the real cold-start observer, without a node.
# Usage: bash tools/scripts/bench_fresh_sync_height_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASELINE=0
ANALYZE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --baseline) BASELINE=1; shift ;;
        --analyze) ANALYZE=1; shift ;;
        *) break ;;
    esac
done
SOURCE="${1:-$ROOT/tools/bench_fresh_sync.c}"
TMP="$(mktemp -d /tmp/zcl-bench-height.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static const char *fixture_state;
static int height_calls, state_calls;
static bool missing_height;
/* Used by the completion-timestamp version of the observer, if present. */
double now_sec(void) { return 11; }
static bool rpc_call(const char *cookie, const char *method, char *buf, int size)
{
    CHECK(strcmp(cookie, "fixture") == 0);
    if (strcmp(method, "syncstate") == 0) {
        state_calls++;
        if (fixture_state == NULL) return false;
        CHECK(snprintf(buf, (size_t)size, "{\"state\":\"%s\"}", fixture_state) < size);
    } else {
        CHECK(strcmp(method, "getblockcount") == 0);
        height_calls++;
        if (missing_height) return false;
        CHECK(snprintf(buf, (size_t)size, "{\"result\":123}") < size);
    }
    return true;
}
C
# Take the production parsers and state observation block, not a model of it.
awk '/^#define TIMEOUT / { print }' "$SOURCE" >> "$TMP/test.c"
awk '/^static bool json_get_str\(/ { copy = 1 }
     /^\/\* Check if a string appears/ || /^enum log_phase/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
static void observe(const char *next, bool fail_height)
{
    static char last_state[64] = "";
    char rpc_buf[4096];
    const char *cookie = "fixture";
    const double elapsed = 10, t0 = 0;
    (void)elapsed; (void)t0;
    fixture_state = next;
    missing_height = fail_height;
C
awk '/^        \/\* Get sync state \*\// { copy = 1 }
     copy { print }
     copy && /strcpy\(last_state, state\)/ { getline; print; exit }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    const bool baseline = strcmp(argv[1], "1") == 0;
    for (int i = 0; i < 100; i++) observe("syncing", false);
    printf("stable_polls=100 state_rpc=%d height_rpc=%d\n", state_calls, height_calls);
    CHECK(state_calls == 100);
    CHECK(height_calls == (baseline ? 100 : 1));
    observe("headers", false);
    observe(NULL, false);
    observe(NULL, false);
    observe("syncing", true);
    observe("syncing", false);
    observe("at_tip", false);
    for (int i = 0; i < 10; i++) observe("at_tip", false);
    printf("total_polls=116 state_rpc=%d height_rpc=%d\n", state_calls, height_calls);
    CHECK(state_calls == 116);
    CHECK(height_calls == (baseline ? 116 : 4));
    puts("PASS: stable polls, state transitions, missing state, missing height, tip transition");
    return 0;
}
C
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror -pedantic \
    "$TMP/test.c" -o "$TMP/test"
if [ "$ANALYZE" = 1 ]; then
    "${CC:-cc}" -std=c23 -Wall -Wextra -Werror -fanalyzer \
        -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
"$TMP/test" "$BASELINE" > "$TMP/output"
cat "$TMP/output"
# Failed state observations retain the sentinel without another RPC.
unknown_height=-1
if [ "$BASELINE" = 1 ]; then unknown_height=123; fi
# Every successful transition retains its contemporaneous height or sentinel.
for expected in 'state=syncing height=123' 'state=headers height=123' \
                "state=unknown height=$unknown_height" 'state=syncing height=-1' \
                'state=at_tip height=123'; do
    grep -F "$expected" "$TMP/output" >/dev/null || {
        echo "FAIL: missing transition: $expected" >&2; exit 1;
    }
done
