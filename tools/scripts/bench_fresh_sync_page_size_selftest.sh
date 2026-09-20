#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic explorer-size regression and optional observer-cost benchmark.
# No node, network, credentials or production datadir is used.
# Usage: bash tools/scripts/bench_fresh_sync_page_size_selftest.sh [--bench] [--analyze] [source.c]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=0
analyze=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --bench) bench=1; shift ;;
        --analyze) analyze=1; shift ;;
        *) break ;;
    esac
done
SOURCE=${1:-$ROOT/tools/bench_fresh_sync.c}
TMP=$(mktemp -d /tmp/zcl-page-size.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
# Check the installed curl's counter against a binary local file as well as
# the stand-in below. file:// requires no listener or network access.
dd if=/dev/zero of="$TMP/body" bs=4096 count=256 2>/dev/null
actual=$(curl -s --max-time 2 -o /dev/null -w '%{size_download}' "file://$TMP/body")
[[ $actual == 1048576 ]] || { echo 'FAIL: curl byte-counter contract' >&2; exit 1; }
if curl -s --max-time 2 -o /dev/null -w '%{size_download}' \
    "file://$TMP/missing" > "$TMP/missing-count"; then
    echo 'FAIL: curl accepted a missing input' >&2
    exit 1
fi
printf 'PASS: installed curl byte-counter and failure status (local files)\n'
cat > "$TMP/test.c" <<'C'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>

#define HTTPSPORT 8447
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
C
awk '/^static int run_cmd\(/ { copy = 1 }
     /^\/\* RPC call/ { copy = 0 }
     /^static int explorer_page_size\(/ { copy = 1 }
     /^\/\* Wait for RPC startup/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
/* Model curl's body/output-counter separation and nonzero transfer status.
 * Payload contains NULs, so the assertion measures bytes rather than text. */
static int mock_curl(int argc, char **argv)
{
    bool discard = false, counter = false, bounded = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0) {
            CHECK(++i < argc && strcmp(argv[i], "/dev/null") == 0);
            discard = true;
        } else if (strcmp(argv[i], "-w") == 0) {
            CHECK(++i < argc && strcmp(argv[i], "%{size_download}") == 0);
            counter = true;
        } else if (strcmp(argv[i], "--max-time") == 0) {
            CHECK(++i < argc && strcmp(argv[i], "2") == 0);
            bounded = true;
        }
    }
    CHECK(bounded);
    const char *mode = getenv("ZCL_PAGE_MODE");
    CHECK(mode != NULL);
    size_t bytes = strcmp(mode, "empty") == 0 ? 0 : 1048576;
    if (!discard) {
        char buf[4096] = {0};
        for (size_t i = 0; i < bytes / sizeof(buf); i++)
            CHECK(fwrite(buf, 1, sizeof(buf), stdout) == sizeof(buf));
    }
    if (counter) CHECK(printf("%zu", bytes) > 0);
    CHECK(fflush(stdout) == 0);
    return strcmp(mode, "failed") == 0 ? 28 : 0;
}

int main(int argc, char **argv)
{
    if (argc > 2) return mock_curl(argc, argv);
    CHECK(setenv("ZCL_PAGE_MODE", "complete", 1) == 0);
    if (argc == 2) {
        struct timespec begin, end;
        CHECK(clock_gettime(CLOCK_MONOTONIC, &begin) == 0);
        for (int i = 0; i < 100; i++)
            CHECK(explorer_page_size("/explorer") == 1048576);
        CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
        printf("100 observations, 1 MiB page: %.6f s\n",
               (double)(end.tv_sec - begin.tv_sec) +
               (double)(end.tv_nsec - begin.tv_nsec) / 1e9);
        return 0;
    }
    const char *paths[] = {"/explorer", "/explorer/factoids",
                           "/explorer/hodl", "/explorer/stats"};
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++)
        CHECK(explorer_page_size(paths[i]) == 1048576);
    CHECK(setenv("ZCL_PAGE_MODE", "empty", 1) == 0);
    CHECK(explorer_page_size("/explorer") == 0);
    CHECK(setenv("ZCL_PAGE_MODE", "failed", 1) == 0);
    CHECK(explorer_page_size("/explorer") == 0);
    puts("PASS: binary byte counts, all four pages, empty body, failed transfer");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -D_POSIX_C_SOURCE=200809L)
"${CC:-cc}" "${flags[@]}" -O2 "$TMP/test.c" -o "$TMP/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
ln -s "$TMP/test" "$TMP/curl"
# Count the redundant tools without relying on strace or wall-time thresholds.
for tool in bash wc; do
    printf '#!/bin/sh\nprintf "%%s\\n" %s >> "$ZCL_PAGE_CALLS"\nexec %s "$@"\n' \
        "$tool" "$(command -v "$tool")" > "$TMP/$tool"
    chmod +x "$TMP/$tool"
done
export ZCL_PAGE_CALLS="$TMP/calls"
: > "$ZCL_PAGE_CALLS"
PATH="$TMP:$PATH" timeout 10 "$TMP/test"
calls=$(wc -l < "$ZCL_PAGE_CALLS")
printf 'six observations: redundant bash/wc invocations=%s\n' "$calls"
if (( bench )); then
    for ((i=0;i<3;i++)); do PATH="$TMP:$PATH" timeout 20 "$TMP/test" --bench; done
fi
[[ $calls == 0 ]] || { echo 'FAIL: redundant page-size tools remain' >&2; exit 1; }
printf 'PASS: page-size observer process budget\n'
