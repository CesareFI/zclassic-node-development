#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the real explorer observer with sparse false marker starts.
# Usage: bash tools/scripts/bench_fresh_sync_sparse_marker_selftest.sh [--analyze] [source.c]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
analyze=0
if [[ ${1:-} == --analyze ]]; then analyze=1; shift; fi
SOURCE=${1:-$ROOT/tools/bench_fresh_sync.c}
TMP=$(mktemp -d /tmp/zcl-sparse-marker.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define HTTPSPORT 8447
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static FILE *body;
static size_t comparisons, searches, bytes_read;
static FILE *fixture_open(const char *cmd, const char *mode)
{
    CHECK(strstr(cmd, "--max-time 2") != NULL);
    CHECK(strcmp(mode, "r") == 0);
    rewind(body);
    return body;
}
static int fixture_close(FILE *f)
{
    CHECK(f == body && feof(f));
    return 0;
}
static size_t counted_read(void *buf, size_t size, size_t count, FILE *f)
{
    size_t n = fread(buf, size, count, f);
    bytes_read += n * size;
    return n;
}
static int counted_compare(const void *a, const void *b, size_t n)
{
    comparisons++;
    return memcmp(a, b, n);
}
static char *counted_search(const char *text, const char *marker)
{
    searches++;
    return strstr(text, marker);
}
#define popen fixture_open
#define pclose fixture_close
#define fread counted_read
#define strstr counted_search
#define memcmp counted_compare
C
awk '/^static void phase_log_normalize\(/ { copy = 1 }
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
    bytes_read = comparisons = searches = 0;
    CHECK(explorer_responding() == expected);
    CHECK(bytes_read == size);
}
int main(void)
{
    static const char marker[] = "Latest Blocks";
    char block[8192];
    /* Real markers immediately after false starts, throughout and beyond
     * the short scan window, plus every overlap position at a read boundary. */
    for (int region = 0; region < 2; region++) {
        size_t base = region == 0 ? 1 : 4080;
        size_t limit = region == 0 ? 160 : 4100;
        for (size_t pos = base; pos < limit; pos++) {
            body = tmpfile();
            CHECK(body != NULL);
            memset(block, 'x', sizeof(block));
            block[0] = 'L';
            memcpy(block + pos, marker, sizeof(marker) - 1);
            CHECK(fwrite(block, 1, sizeof(block), body) == sizeof(block));
            CHECK(fflush(body) == 0);
            observe(true, sizeof(block));
            CHECK(fclose(body) == 0);
        }
    }
    /* Candidate-rich and NUL-containing chunks must retain exact byte
     * matching; a gap must never join the two halves of a marker. */
    for (int mode = 0; mode < 3; mode++) {
        body = tmpfile();
        CHECK(body != NULL);
        memset(block, mode == 0 ? 'L' : '\0', sizeof(block));
        memcpy(block + 63, "Latest", 6);
        memcpy(block + 70, " Blocks", 7);
        if (mode == 2)
            memcpy(block + sizeof(block) - (sizeof(marker) - 1), marker,
                   sizeof(marker) - 1);
        CHECK(fwrite(block, 1, sizeof(block), body) == sizeof(block));
        CHECK(fflush(body) == 0);
        observe(mode == 2, sizeof(block));
        CHECK(fclose(body) == 0);
    }
    /* One false start per 8192 bytes previously scanned half of a 16 MiB
     * body byte by byte. Gate work, not wall time, independently of load. */
    body = tmpfile();
    CHECK(body != NULL);
    memset(block, 'x', sizeof(block));
    block[0] = 'L';
    const size_t size = 16 * 1024 * 1024;
    for (size_t n = 0; n < size; n += sizeof(block))
        CHECK(fwrite(block, 1, sizeof(block), body) == sizeof(block));
    CHECK(fflush(body) == 0);
    observe(false, size);
    printf("sparse bytes=%zu comparisons=%zu searches=%zu\n",
           bytes_read, comparisons, searches);
    CHECK(comparisons == size / 8192 && searches == 0);
    CHECK(fclose(body) == 0);
    puts("PASS: sparse scan work, window boundaries, overlap, binary gaps, full drain");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L)
"${CC:-cc}" "${flags[@]}" -O2 "$TMP/test.c" -o "$TMP/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
timeout 30 "$TMP/test"
