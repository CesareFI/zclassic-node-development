#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the production explorer observer without a node or network.
# Usage: bash tools/scripts/bench_fresh_sync_readiness_selftest.sh [--bench] [--analyze] [source.c]
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
TMP=$(mktemp -d /tmp/zcl-explorer-ready.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define HTTPSPORT 8447
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
C
awk '/^static int run_cmd\(/ { copy = 1 }
     /^\/\* RPC call/ { copy = 0 }
     /^static void phase_log_normalize\(/ { copy = 1 }
     /^static bool phase_log_scan_chunk\(/ { copy = 0 }
     /^static bool explorer_responding\(/ { copy = 1 }
     /^static int explorer_page_size\(/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
static int mock_curl(int argc, char **argv)
{
    bool bounded = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--max-time") == 0) {
            CHECK(++i < argc && strcmp(argv[i], "2") == 0);
            bounded = true;
        }
    }
    CHECK(bounded);
    const char *position = getenv("ZCL_READY_POSITION");
    const char *length = getenv("ZCL_READY_LENGTH");
    const char *mode = getenv("ZCL_READY_MODE");
    CHECK(position && length && mode);
    long at = strtol(position, NULL, 10);
    long bytes = strtol(length, NULL, 10);
    const char *marker = strcmp(mode, "split-line") == 0 ? "Latest\nBlocks" : "Latest Blocks";
    for (long base = 0; base < bytes; base += 4096) {
        char buf[4096];
        size_t n = bytes - base < 4096 ? (size_t)(bytes - base) : sizeof(buf);
        memset(buf, 'x', n);
        for (size_t i = 0; i < n; i++) {
            long delta = base + (long)i - at;
            if (at >= 0 && delta >= 0 && delta < 13) buf[i] = marker[delta];
        }
        CHECK(fwrite(buf, 1, n, stdout) == n);
    }
    CHECK(fflush(stdout) == 0);
    return strcmp(mode, "failed") == 0 ? 28 : 0;
}

static void fixture(const char *position, const char *length, const char *mode, bool expected)
{
    CHECK(setenv("ZCL_READY_POSITION", position, 1) == 0);
    CHECK(setenv("ZCL_READY_LENGTH", length, 1) == 0);
    CHECK(setenv("ZCL_READY_MODE", mode, 1) == 0);
    CHECK(explorer_responding() == expected);
}

int main(int argc, char **argv)
{
    if (argc > 2) return mock_curl(argc, argv);
    /* Keep the original command reader in the extracted fixture exercised. */
    char buf[2];
    CHECK(run_cmd("printf ''", buf, sizeof(buf)) == 0);
    if (argc == 2) {
        struct timespec begin, end;
        CHECK(clock_gettime(CLOCK_MONOTONIC, &begin) == 0);
        for (int i = 0; i < 100; i++) fixture("4095", "1048576", "ok", true);
        CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
        printf("100 observations, 1 MiB page: %.6f s\n",
               (double)(end.tv_sec - begin.tv_sec) +
               (double)(end.tv_nsec - begin.tv_nsec) / 1e9);
        return 0;
    }
    fixture("0", "13", "ok", true);
    fixture("8179", "8192", "ok", true);
    for (int pos = 4084; pos <= 4096; pos++) {
        char position[32];
        CHECK(snprintf(position, sizeof(position), "%d", pos) > 0);
        fixture(position, "8192", "ok", true);
    }
    fixture("-1", "8192", "ok", false);
    fixture("0", "0", "ok", false);
    fixture("0", "12", "ok", false);
    fixture("0", "8192", "split-line", false);
    fixture("0", "1048576", "failed", false);
    puts("PASS: full and split markers, end marker, missing/empty/partial markers, failed transfer");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L)
"${CC:-cc}" "${flags[@]}" -O2 "$TMP/test.c" -o "$TMP/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
ln -s "$TMP/test" "$TMP/curl"
# Count actual redundant commands; timing is descriptive, never a pass gate.
for tool in bash grep; do
    printf '#!/bin/sh\nprintf "%%s\\n" %s >> "$SELFTEST_READY_CALLS"\nexec %s "$@"\n' \
        "$tool" "$(command -v "$tool")" > "$TMP/$tool"
    chmod +x "$TMP/$tool"
done
export SELFTEST_READY_CALLS="$TMP/calls"
: > "$SELFTEST_READY_CALLS"
PATH="$TMP:$PATH" timeout 10 "$TMP/test"
calls=$(wc -l < "$SELFTEST_READY_CALLS")
printf '20 readiness observations: redundant bash/grep invocations=%s\n' "$calls"
if (( bench )); then
    for ((i=0;i<3;i++)); do PATH="$TMP:$PATH" timeout 20 "$TMP/test" --bench; done
fi
[[ $calls == 0 ]] || { echo 'FAIL: redundant readiness tools remain' >&2; exit 1; }
printf 'PASS: explorer-readiness observer process budget\n'
