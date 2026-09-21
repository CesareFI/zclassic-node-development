#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise production HTTP observers with a controlled curl stand-in.
# No node, network, datadir or real credentials participate.
# Usage: bash tools/scripts/bench_fresh_sync_deadline_selftest.sh [--analyze] [source.c]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
analyze=false
if [ "${1:-}" = --analyze ]; then analyze=true; shift; fi
SOURCE="${1:-$ROOT/tools/bench_fresh_sync.c}"
TMP="$(mktemp -d /tmp/zcl-bench-deadline.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
#include <stdbool.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "platform/time_compat.h"

#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
#define RPCPORT 18247
#define HTTPSPORT 8447
C
awk '/^static int run_cmd\(/ { copy = 1 }
     /^\/\* Extract a string/ { copy = 0 }
     /^static void phase_log_normalize\(/ { copy = 1 }
     /^static bool phase_log_scan_chunk\(|^static bool phase_log_poll\(/ { copy = 0 }
     /^static bool explorer_responding\(/ { copy = 1 }
     /^static void startup_progress\(/ { copy = 0 }
     /^int main\(/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
/* Simulate a six-second stalled transfer. Honor curl's --max-time interface;
 * return its timeout status 28 with any prefix already written still visible.
 * This tests the caller's command and observation contract, not libcurl. */
static int mock_curl(int argc, char **argv)
{
    unsigned int deadline = 0;
    bool discard = false, counter = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--max-time") == 0) {
            CHECK(i + 1 < argc);
            char *end;
            unsigned long n = strtoul(argv[++i], &end, 10);
            CHECK(*end == '\0' && n > 0 && n <= 6);
            deadline = (unsigned int)n;
        } else if (strcmp(argv[i], "-o") == 0) {
            CHECK(i + 1 < argc && strcmp(argv[++i], "/dev/null") == 0);
            discard = true;
        } else if (strcmp(argv[i], "-w") == 0) {
            CHECK(i + 1 < argc && strcmp(argv[++i], "%{size_download}") == 0);
            counter = true;
        }
    }
    const char *mode = getenv("ZCL_BENCH_HTTP_FIXTURE");
    CHECK(mode != NULL);
    if (strcmp(mode, "fast-page") == 0 || strcmp(mode, "partial-page") == 0) {
        if (!discard) CHECK(fputs("Latest Blocks", stdout) >= 0);
        if (counter) CHECK(fputs("13", stdout) >= 0);
        CHECK(fflush(stdout) == 0);
        if (strcmp(mode, "fast-page") == 0) return 0;
    } else if (strcmp(mode, "fast") == 0 || strcmp(mode, "partial") == 0) {
        CHECK(fputs("{\"state\":\"at_tip\"}", stdout) >= 0);
        CHECK(fflush(stdout) == 0);
        if (strcmp(mode, "fast") == 0) return 0;
    }
    sleep(deadline > 0 && deadline < 6 ? deadline : 6);
    return deadline > 0 && deadline < 6 ? 28 : 18;
}

static void run_deadline_case(int mode)
{
    char buf[256];
    const char *fixture = mode >= 4 ? "partial-page" :
                          mode == 1 ? "partial" : "silent";
    CHECK(setenv("ZCL_BENCH_HTTP_FIXTURE", fixture, 1) == 0);
    int64_t begin = platform_time_monotonic_us();
    bool observed;
    if (mode < 2) {
        observed = rpc_call("fixture:fixture", "syncstate", buf, sizeof(buf));
        CHECK(buf[0] == '\0');
    } else if (mode == 2 || mode == 4) {
        observed = explorer_responding();
    } else {
        observed = explorer_page_size("/explorer") != 0;
    }
    double elapsed = (double)(platform_time_monotonic_us() - begin) / 1e6;
    printf("mode=%d elapsed=%.3fs observed=%d\n", mode, elapsed, observed);
    CHECK(!observed);
    /* Wide scheduling tolerance around the production two-second deadline. */
    CHECK(elapsed >= 1.0 && elapsed < 4.0);
}

int main(int argc, char **argv)
{
    if (argc > 1) return mock_curl(argc, argv);
    char buf[256];
    CHECK(setenv("ZCL_BENCH_HTTP_FIXTURE", "fast", 1) == 0);
    CHECK(rpc_call("fixture:fixture", "syncstate", buf, sizeof(buf)));
    CHECK(strcmp(buf, "{\"state\":\"at_tip\"}") == 0);
    puts("PASS: successful RPC remains observable");
    CHECK(setenv("ZCL_BENCH_HTTP_FIXTURE", "fast-page", 1) == 0);
    CHECK(explorer_responding());
    CHECK(explorer_page_size("/explorer") == 13);
    puts("PASS: successful explorer readiness and size remain observable");
    CHECK(fflush(NULL) == 0);
    pid_t children[6];
    int failures = 0;
    for (int mode = 0; mode < 6; mode++) {
        children[mode] = fork();
        if (children[mode] < 0) {
            perror("fork deadline fixture");
            failures++;
            continue;
        }
        if (children[mode] == 0) {
            run_deadline_case(mode);
            return 0;
        }
    }
    for (int mode = 0; mode < 6; mode++) {
        if (children[mode] < 0) continue;
        int status;
        pid_t waited;
        do {
            waited = waitpid(children[mode], &status, 0);
        } while (waited < 0 && errno == EINTR);
        if (waited != children[mode] || !WIFEXITED(status) ||
            WEXITSTATUS(status) != 0) {
            fprintf(stderr, "FAIL: deadline mode %d child status=%d\n",
                    mode, waited == children[mode] ? status : -1);
            failures++;
        }
    }
    CHECK(failures == 0);
    puts("PASS: silent and partial RPC, explorer readiness and page-size calls are bounded");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -D_DEFAULT_SOURCE
    -I"$ROOT/platform/modules/platform/include"
    -I"$ROOT/platform/modules/base/include" -I"$ROOT/platform/modules/util/include")
"${CC:-cc}" "${flags[@]}" -O2 "$TMP/test.c" \
    "$ROOT/platform/modules/platform/src/clock.c" \
    "$ROOT/platform/modules/base/src/log_level.c" -o "$TMP/test"
if "$analyze"; then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
ln -s "$TMP/test" "$TMP/curl"
PATH="$TMP:$PATH" timeout 20 "$TMP/test"
