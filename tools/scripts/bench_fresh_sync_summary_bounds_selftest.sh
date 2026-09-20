#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Bound repeated summary searches to the remaining candidate interval.
# Usage: bash tools/scripts/bench_fresh_sync_summary_bounds_selftest.sh [--baseline] [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/zcl-summary-bounds.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#define _POSIX_C_SOURCE 200809L
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static bool counting;
static size_t search_bytes;
static char *search(const char *s, const char *marker)
{
    if (counting) search_bytes += strlen(s);
    return strstr(s, marker);
}
#define strstr search
C
sed -n '/^static off_t snapshot_log_chunk(/,/^}/p' "$subject" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef strstr
static double now(void)
{
    struct timespec ts;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    char text[65537], original[sizeof(text)];
    /* Dense older summaries followed by an unrelated suffix and candidate. */
    for (size_t length = 16384; length <= 65536; length *= 4) {
        memset(text, 'x', length);
        for (size_t pos = 0; pos <= 1024; pos += 16)
            memcpy(text + pos, "UTXOs in", 8);
        text[length - 1] = 'U';
        text[length] = '\0';
        memcpy(original, text, length + 1);
        counting = true;
        search_bytes = 0;
        CHECK(snapshot_log_chunk(text, length, "UTXOs in", 8) == 1024);
        CHECK(memcmp(text, original, length + 1) == 0);
        printf("length=%zu search_input_bytes=%zu\n", length, search_bytes);
        if (!baseline) CHECK(search_bytes <= length * 10);
        counting = false;
        for (int trial = 0; trial < 3; trial++) {
            double start = now();
            for (int i = 0; i < 20000; i++)
                CHECK(snapshot_log_chunk(text, length, "UTXOs in", 8) == 1024);
            CHECK(memcmp(text, original, length + 1) == 0);
            printf("length=%zu trial=%d lookups=20000 seconds=%.6f\n",
                   length, trial + 1, now() - start);
        }
    }
    /* Exercise every candidate boundary and confirm the borrowed buffer is
     * restored. The simple independent oracle enumerates all matches. */
    for (size_t length = 128; length < 2048; length += 17) {
        for (size_t gap = 8; gap < length; gap += 13) {
            memset(text, 'U', length);
            for (size_t pos = 0; pos + 8 < length - gap; pos += 8)
                memcpy(text + pos, "UTXOs in", 8);
            text[length] = '\0';
            memcpy(original, text, length + 1);
            off_t expected = -1;
            const char *p = text;
            while ((p = strstr(p, "UTXOs in")) != NULL) expected = p++ - text;
            CHECK(snapshot_log_chunk(text, length, "UTXOs in", 8) == expected);
            CHECK(memcmp(text, original, length + 1) == 0);
        }
    }
    puts("PASS: latest match and buffer preservation");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
"${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
timeout 30 "$fixture/test" "$baseline"
