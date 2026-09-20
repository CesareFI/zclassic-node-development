#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Latest-summary fallback work on isolated text buffers; no node or network.
# Usage: bash tools/scripts/bench_fresh_sync_summary_fallback_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0 analyze=0
while [[ ${1:-} == --* ]]; do
    case $1 in
        --baseline) baseline=1 ;;
        --analyze) analyze=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
source_file=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-summary-fallback.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static size_t searches;
static char *counted_search(const char *text, const char *marker)
{
    searches++;
    return strstr(text, marker);
}
#define strstr counted_search
C
awk '/^static off_t snapshot_log_chunk\(/ { copy = 1; starts++ }
     /^static off_t snapshot_log_match\(/ { copy = 0; ends++ }
     copy { print }
     END { if (starts != 1 || ends != 1) exit 1 }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef strstr
static double now(void)
{
    struct timespec ts;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
static void check(char *text, size_t size)
{
    off_t expected = -1;
    for (const char *p = strstr(text, "UTXOs in"); p; p = strstr(p + 1, "UTXOs in"))
        expected = (off_t)(p - text);
    CHECK(snapshot_log_chunk(text, size, "UTXOs in", 8) == expected);
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    char text[65537];
    /* Different extents, densities and suffix lengths compare against an
     * independent linear oracle. Include empty and partial final markers. */
    const size_t lengths[] = {0, 7, 8, 63, 64, 65, 255, 256, 4096, 16384, 65536};
    const size_t gaps[] = {8, 9, 16, 63, 64, 65, 257};
    for (size_t l = 0; l < sizeof(lengths) / sizeof(lengths[0]); l++) {
        size_t size = lengths[l];
        for (size_t g = 0; g < sizeof(gaps) / sizeof(gaps[0]); g++) {
            for (size_t suffix = 0; suffix <= 129; suffix++) {
                memset(text, 'U', size);
                text[size] = '\0';
                for (size_t pos = 0; pos + 8 + suffix <= size; pos += gaps[g])
                    memcpy(text + pos, "UTXOs in", 8);
                check(text, size);
            }
        }
    }
    const size_t size = sizeof(text) - 1;
    for (int mode = 0; mode < 5; mode++) {
        memset(text, 'U', size);
        text[size] = '\0';
        off_t expected = -1;
        if (mode == 1) { memcpy(text, "UTXOs in", 8); expected = 0; }
        if (mode == 2 || mode == 3) {
            for (size_t pos = 0; pos + 512 < size; pos += 16) {
                memcpy(text + pos, "UTXOs in", 8);
                expected = (off_t)pos;
            }
            if (mode == 3) {
                expected = (off_t)size - 8;
                memcpy(text + expected, "UTXOs in", 8);
            }
        }
        if (mode == 4) {
            for (size_t pos = 0; pos < 7 * 16; pos += 16) {
                memcpy(text + pos, "UTXOs in", 8);
                expected = (off_t)pos;
            }
        }
        for (int trial = 0; trial < 3; trial++) {
            searches = 0;
            double start = now();
            for (int repeat = 0; repeat < 1000; repeat++)
                CHECK(snapshot_log_chunk(text, size, "UTXOs in", 8) == expected);
            printf("mode=%d trial=%d scans=1000 bytes=%zu searches=%zu seconds=%.6f\n",
                   mode, trial + 1, size, searches, now() - start);
            if (!baseline) CHECK(searches <= (mode == 2 ? 24u : mode == 4 ? 8u : 2u) * 1000);
        }
    }
    puts(baseline ? "BASELINE: fallback cost measured" :
         "PASS: latest offsets, partial markers, fallback and sparse search budgets");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$baseline"
