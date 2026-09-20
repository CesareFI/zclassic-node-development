#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Bound readiness marker search work; measure the actual observer on local files.
# Usage: bash tools/scripts/bench_fresh_sync_explorer_scan_selftest.sh [--measure] [--analyze] [source.c]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
measure=0
analyze=0
while [[ ${1:-} == --* ]]; do
    case $1 in
        --measure) measure=1 ;;
        --analyze) analyze=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
SOURCE=${1:-$ROOT/tools/bench_fresh_sync.c}
TMP=$(mktemp -d /tmp/zcl-explorer-scan.XXXXXX)
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
static FILE *body;
static size_t comparisons, searches, bytes_read, read_calls;
static int close_status;
static bool read_error;
static FILE *fixture_open(const char *cmd, const char *mode)
{
    CHECK(strstr(cmd, "--max-time 2") != NULL);
    CHECK(strcmp(mode, "r") == 0);
    rewind(body);
    return body;
}
static int fixture_close(FILE *f)
{
    CHECK(f == body && feof(f)); /* Even a match must drain the response. */
    return close_status;
}
static int fixture_error(FILE *f)
{
    CHECK(f == body);
    return read_error;
}
static size_t fixture_read(void *buf, size_t size, size_t count, FILE *f)
{
    read_calls++;
    size_t n = fread(buf, size, count, f);
    bytes_read += n * size;
    return n;
}
static int counted_compare(const void *a, const void *b, size_t n)
{
#ifndef SCAN_TIMING
    comparisons++;
#endif
    return memcmp(a, b, n);
}
static inline char *counted_search(const char *text, const char *marker)
{
#ifndef SCAN_TIMING
    searches++;
#endif
    return strstr(text, marker);
}
#define popen fixture_open
#define pclose fixture_close
#define ferror fixture_error
#define fread fixture_read
#define strstr counted_search
#define memcmp counted_compare
C
awk '/^static void phase_log_normalize\(/ { copy = 1; sub(/static void/, "static inline void") }
     /^static bool phase_log_poll\(/ { copy = 0 }
     /^static bool explorer_responding\(/ { copy = 1 }
     /^static int explorer_page_size\(/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
#undef fread
#undef strstr
#undef memcmp
static void observe(bool expected, size_t size)
{
    bytes_read = 0;
    read_calls = 0;
    CHECK(explorer_responding() == expected);
    CHECK(bytes_read == size);
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool measure = strcmp(argv[1], "1") == 0;
    static const char marker[] = "Latest Blocks";
    char block[131072];
    /* NUL-filled responses with dense false starts force normalization;
     * every marker split still matches, and errors still reject the body. */
    for (size_t boundary = 4096; boundary <= 65536; boundary *= 16) {
        for (size_t pos = boundary - 12; pos <= boundary; pos++) {
            body = tmpfile();
            CHECK(body != NULL);
            memset(block, 0, sizeof(block));
            block[0] = block[1] = 'L';
            memcpy(block + pos, marker, sizeof(marker) - 1);
            CHECK(fwrite(block, 1, sizeof(block), body) == sizeof(block));
            CHECK(fflush(body) == 0);
            observe(true, sizeof(block));
            close_status = 28;
            observe(false, sizeof(block));
            close_status = 0;
            read_error = true;
            observe(false, sizeof(block));
            read_error = false;
            CHECK(fclose(body) == 0);
        }
    }
    for (size_t len = 0; len <= sizeof(marker) - 1; len++) {
        body = tmpfile();
        CHECK(body != NULL);
        CHECK(fwrite(marker, 1, len, body) == len);
        CHECK(fflush(body) == 0);
        observe(len == sizeof(marker) - 1, len);
        CHECK(fclose(body) == 0);
    }
    for (size_t split = 1; split < sizeof(marker) - 1; split++) {
        body = tmpfile();
        CHECK(body != NULL);
        CHECK(fwrite("LL", 1, 2, body) == 2); /* Force the dense path. */
        CHECK(fwrite(marker, 1, split, body) == split);
        CHECK(fputc('\0', body) != EOF);
        CHECK(fwrite(marker + split, 1, sizeof(marker) - 1 - split, body) ==
              sizeof(marker) - 1 - split);
        CHECK(fflush(body) == 0);
        observe(false, sizeof(marker) + 2); /* Never join text across a NUL. */
        CHECK(fclose(body) == 0);
    }
    /* Warm 16 MiB body: absent, dense/sparse false starts, late/early real
     * markers, and dense two-byte prefixes that still need full comparison.
     * Wall time is descriptive, never a gate. */
    const size_t size = 16 * 1024 * 1024;
    for (int mode = 0; mode < 6; mode++) {
        body = tmpfile();
        CHECK(body != NULL);
        memset(block, mode == 1 ? 'L' : 'x', sizeof(block));
        if (mode == 2)
            for (size_t i = 0; i < sizeof(block); i += 8192) block[i] = 'L';
        if (mode == 4) memcpy(block, marker, sizeof(marker) - 1);
        if (mode == 5)
            for (size_t i = 0; i < sizeof(block); i += 2) {
                block[i] = 'L';
                block[i + 1] = 'a';
            }
        for (size_t n = 0; n < size; n += sizeof(block))
            CHECK(fwrite(block, 1, sizeof(block), body) == sizeof(block));
        if (mode == 3) {
            CHECK(fseeko(body, (off_t)(size - (sizeof(marker) - 1)), SEEK_SET) == 0);
            CHECK(fwrite(marker, 1, sizeof(marker) - 1, body) == sizeof(marker) - 1);
        }
        CHECK(fflush(body) == 0);
        const bool expected = mode == 3 || mode == 4;
        observe(expected, size); /* Warm the same fixture in both versions. */
        printf("mode=%d reads_per_poll=%zu bytes_per_poll=%zu\n", mode, read_calls, size);
        if (!measure) CHECK(read_calls <= size / 65536 + 1);
        for (int run = 0; run < 3; run++) {
            struct timespec begin, end;
            comparisons = searches = 0;
            CHECK(clock_gettime(CLOCK_MONOTONIC, &begin) == 0);
            for (int i = 0; i < 5; i++) observe(expected, size);
            CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
            printf("mode=%d run=%d polls=5 bytes_per_poll=%zu ", mode, run, size);
#ifdef SCAN_TIMING
            printf("searches=not-counted ");
#else
            printf("comparisons=%zu searches=%zu ", comparisons, searches);
#endif
            printf("seconds=%.6f\n",
                   (double)(end.tv_sec - begin.tv_sec) +
                   (double)(end.tv_nsec - begin.tv_nsec) / 1e9);
            if (!measure) {
                CHECK(searches == (mode == 1 || mode == 5 ? 5 * (size / 65536) : 0));
                if (mode == 0 || mode == 1 || mode == 5) CHECK(comparisons == 0);
                if (mode == 2) CHECK(comparisons == 5 * (size / 8192));
                if (mode == 3 || mode == 4) CHECK(comparisons == 5);
            }
        }
        CHECK(fclose(body) == 0);
    }
    puts(measure ? "PASS: behavior checks and descriptive timings" :
                   "PASS: marker boundaries, binary bodies, full drain, errors, chunk search budget");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L)
if (( measure )); then flags+=(-DSCAN_TIMING); fi
"${CC:-cc}" "${flags[@]}" -O2 "$TMP/test.c" -o "$TMP/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
timeout 30 "$TMP/test" "$measure"
