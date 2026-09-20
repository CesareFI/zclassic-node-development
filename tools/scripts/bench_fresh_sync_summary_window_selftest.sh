#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Bound recent-summary candidate lookup; no node, network or datadir.
# Usage: bash tools/scripts/bench_fresh_sync_summary_window_selftest.sh [--baseline] [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/zcl-summary-window.XXXXXX)
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
static size_t searched;
static bool count_search;
static char *observe_last(const char *s, int c)
{
    if (count_search) searched += strlen(s);
    return strrchr(s, c);
}
#define strrchr observe_last
C
sed -n '/^static off_t snapshot_log_bisect(/,/^}/p' "$subject" >> "$fixture/test.c"
sed -n '/^static off_t snapshot_log_chunk(/,/^}/p' "$subject" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef strrchr
static double now(void)
{
    struct timespec ts;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
static off_t oracle(const char *text)
{
    off_t last = -1;
    const char *p = text;
    while ((p = strstr(p, "UTXOs in")) != NULL) last = p++ - text;
    return last;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    char text[65537];
    /* Each possible short-buffer position, including the suffix boundary,
     * empty input, incomplete trailing candidates and dense false candidates. */
    for (size_t length = 0; length <= 256; length++) {
        for (size_t position = 0; position <= length; position++) {
            memset(text, 'U', length);
            text[length] = '\0';
            if (length >= 8) memcpy(text, "UTXOs in", 8);
            if (position + 8 <= length) memcpy(text + position, "UTXOs in", 8);
            CHECK(snapshot_log_chunk(text, length, "UTXOs in", 8) == oracle(text));
        }
    }
    const size_t lengths[] = {16384, 65536};
    for (size_t n = 0; n < sizeof(lengths) / sizeof(lengths[0]); n++) {
        size_t length = lengths[n];
        memset(text, 'x', length);
        text[length] = '\0';
        memcpy(text + length - 16, "UTXOs in", 8);
        count_search = true;
        searched = 0;
        CHECK(snapshot_log_chunk(text, length, "UTXOs in", 8) == (off_t)length - 16);
        printf("buffer_bytes=%zu candidate_search_bytes=%zu\n", length, searched);
        if (!baseline) CHECK(searched <= 64);
        count_search = false;
        for (int trial = 0; trial < 3; trial++) {
            double start = now();
            for (int repeat = 0; repeat < 200000; repeat++)
                CHECK(snapshot_log_chunk(text, length, "UTXOs in", 8) == (off_t)length - 16);
            printf("buffer_bytes=%zu trial=%d lookups=200000 seconds=%.6f\n",
                   length, trial + 1, now() - start);
        }
        /* An unrelated late candidate must not hide the older summary. */
        text[length - 1] = 'U';
        CHECK(snapshot_log_chunk(text, length, "UTXOs in", 8) == oracle(text));
        memset(text, 'x', length);
        memcpy(text + 17, "UTXOs in", 8);
        CHECK(snapshot_log_chunk(text, length, "UTXOs in", 8) == 17);
        memset(text, 'x', length);
        CHECK(snapshot_log_chunk(text, length, "UTXOs in", 8) == -1);
    }
    puts("PASS: exact latest match, suffix boundaries, fallback and search budget");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
"${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
timeout 20 "$fixture/test" "$baseline"
