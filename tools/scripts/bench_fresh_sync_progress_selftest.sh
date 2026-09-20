#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the startup progress reader against bounded local log fixtures.
# Usage: bash tools/scripts/bench_fresh_sync_progress_selftest.sh [--bench] [--analyze] [source.c]
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
TMP=$(mktemp -d /tmp/zcl-startup-progress.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static unsigned int commands;
static size_t requested_bytes;
static bool short_read;
static size_t counted_fread(void *out, size_t size, size_t count, FILE *f)
{
    requested_bytes += size * count;
    if (short_read) return 0;
    return fread(out, size, count, f);
}
#define fread counted_fread
static FILE *counted_popen(const char *cmd, const char *mode)
{
    commands++;
    return popen(cmd, mode);
}
#define popen counted_popen
C
# Keep the real fallback command reader for before/after measurements; external
# linkage avoids an unused-function warning when the new path needs no command.
awk '/^static void startup_log_tail\(/ { copy = 1 }
     /^\/\* Capture complete/ { copy = 0 }
     /^static int run_cmd\(/ { copy = 1; sub(/^static /, "") }
     /^\/\* RPC call/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
static void observe(const char *logfile, char *out)
{
    requested_bytes = 0;
C
awk '/^static void startup_progress\(/ { startup = 1 }
     startup && /char line\[256\]/ { copy = 1 }
     copy && /printf\("  \[%.0fs\]/ { exit }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
    strcpy(out, line);
    CHECK(requested_bytes <= 256);
}
static void fixture(const char *path, size_t prefix, const char *body, size_t size,
                    const char *expected)
{
    FILE *f = fopen(path, "wb");
    CHECK(f != NULL);
    if (prefix > 0) {
        /* A sparse long preceding line must not change the final observation. */
        CHECK(fseeko(f, (off_t)prefix - 1, SEEK_SET) == 0);
        CHECK(fputc('\n', f) != EOF);
    }
    CHECK(fwrite(body, 1, size, f) == size);
    CHECK(fclose(f) == 0);
    char out[256];
    memset(out, 'z', sizeof(out));
    observe(path, out);
    CHECK(strcmp(out, expected) == 0);
}
int main(int argc, char **argv)
{
    CHECK(argc == 3);
    const char *path = argv[1];
    fixture(path, 0, "", 0, "");
    fixture(path, 0, "\n", 1, "");
    fixture(path, 0, "one\ntwo\n", 8, "two");
    fixture(path, 0, "one\ntwo", 7, "two");
    fixture(path, 0, "one\n\n", 5, "");
    fixture(path, 0, "one\r\n", 5, "one\r");
    fixture(path, 0, "x\0y\n", 4, "x");
    char line[1024];
    memset(line, 'x', sizeof(line));
    line[254] = '\n';
    char expected[256];
    memset(expected, 'x', 254); expected[254] = '\0';
    fixture(path, 0, line, 255, expected);
    line[254] = 'x'; expected[254] = 'x'; expected[255] = '\0';
    fixture(path, 0, line, 255, expected);
    fixture(path, 0, line, 256, "");
    line[255] = '\n';
    fixture(path, 0, line, 256, "");
    line[255] = 'x';
    fixture(path, 0, line, sizeof(line), "");
    line[1023] = '\n';
    fixture(path, 0, line, sizeof(line), "");
    fixture(path, 4096, "last\n", 5, "last");
    fixture(path, 4096, line, 255, expected);
    fixture(path, 4096, line, 256, "");
    fixture(path, 4096, "\n", 1, "");
    fixture(path, 64 * 1024 * 1024, "progress\n", 9, "progress");
    char out[256];
    short_read = true;
    observe(path, out);
    CHECK(out[0] == '\0');
    short_read = false;
    if (strcmp(argv[2], "1") == 0) {
        for (int run = 0; run < 3; run++) {
            struct timespec start, end;
            CHECK(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
            for (int i = 0; i < 500; i++) {
                observe(path, out);
                CHECK(strcmp(out, "progress") == 0);
            }
            CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
            printf("500 progress observations, 64 MiB log, run %d: %.6f s\n", run + 1,
                   (double)(end.tv_sec - start.tv_sec) +
                   (double)(end.tv_nsec - start.tv_nsec) / 1e9);
        }
    }
    CHECK(unlink(path) == 0);
    observe(path, out);
    CHECK(out[0] == '\0');
    puts("PASS: complete/unterminated/empty/binary lines, exact fit, overflow, truncation, missing log");
    printf("startup progress subprocesses: %u\n", commands);
    CHECK(commands == 0);
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -D_POSIX_C_SOURCE=200809L)
"${CC:-cc}" "${flags[@]}" -O2 "$TMP/test.c" -o "$TMP/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
timeout 15 "$TMP/test" "$TMP/node.log" "$bench"
