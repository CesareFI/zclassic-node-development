#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure failed state observations using the production block and a fake clock.
# Usage: bash tools/scripts/bench_fresh_sync_unavailable_rpc_selftest.sh [--baseline] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
source_file=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/zcl-unavailable-rpc.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static double clock_sec;
static int state_calls, height_calls;
static bool unavailable;
static double now_sec(void) { return clock_sec; }
static bool rpc_call(const char *cookie, const char *method, char *buf, int size)
{
    CHECK(strcmp(cookie, "fixture") == 0);
    bool state = strcmp(method, "syncstate") == 0;
    CHECK(state || strcmp(method, "getblockcount") == 0);
    if (state) state_calls++; else height_calls++;
    clock_sec += unavailable ? 2.0 : 0.01;
    if (unavailable) {
        buf[0] = '\0';
        return false;
    }
    CHECK(snprintf(buf, (size_t)size, "%s",
                   state ? "{\"state\":\"at_tip\"}" : "{\"result\":123}") < size);
    return true;
}
C
awk '/^#define TIMEOUT / { print }
     /^static bool json_get_str\(/ { copy = 1 }
     /^enum log_phase/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
static long observe(char *last_state)
{
    const char *cookie = "fixture";
    char rpc_buf[4096];
    double t0 = 0;
C
awk '/^        \/\* Get sync state \*\// { copy = 1 }
     copy { print }
     copy && /strcpy\(last_state, state\)/ { getline; print; exit }' \
    "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
    return height;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    const char *previous[] = {"", "syncing", "at_tip", "unknown"};
    for (size_t i = 0; i < sizeof(previous) / sizeof(previous[0]); i++) {
        char last_state[64];
        strcpy(last_state, previous[i]);
        clock_sec = 1;
        state_calls = height_calls = 0;
        unavailable = true;
        CHECK(observe(last_state) == -1);
        CHECK(strcmp(last_state, "unknown") == 0);
        CHECK(state_calls == 1);
        CHECK(height_calls == (baseline && i < 3 ? 1 : 0));
        CHECK(clock_sec == (baseline && i < 3 ? 5 : 3));
        printf("previous=%s unavailable_observation_seconds=%.0f height_rpc=%d\n",
               previous[i], clock_sec - 1, height_calls);
        /* Repeated failures remain one state call; recovery still gets height. */
        int calls = height_calls;
        CHECK(observe(last_state) == -1 && height_calls == calls);
        unavailable = false;
        CHECK(observe(last_state) == 123 && height_calls == calls + 1);
        CHECK(strcmp(last_state, "at_tip") == 0);
        CHECK(observe(last_state) == -1 && height_calls == calls + 1);
    }
    puts("PASS: first failure, lost syncing/tip observations, repeated failure, recovery");
}
C
flags=(-std=c23 -O2 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" "$fixture/test.c" -o "$fixture/test"
"${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
timeout 5 "$fixture/test" "$baseline"
