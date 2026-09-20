#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Snapshot-summary lookup with unrelated trailing candidates; no node/network.
# Usage: bash tools/scripts/bench_fresh_sync_summary_suffix_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-summary-suffix.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
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
awk '/^static off_t snapshot_log_(chunk|match)\(/ { if (!copy) starts++; copy = 1 }
     /^\/\* A displayable line/ { copy = 0; ends++ }
     copy { print }
     END { if (starts != 1 || ends != 1) exit 1 }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef strstr
static FILE *text_file(const char *text, size_t length)
{
    FILE *f = tmpfile();
    CHECK(f != NULL);
    CHECK(setvbuf(f, NULL, _IONBF, 0) == 0);
    CHECK(fwrite(text, 1, length, f) == length);
    return f;
}
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
    char text[16384];
    /* Latest match must win across both sides of the bounded search window.
     * Older matches make falling back to the first occurrence observable. */
    const size_t distances[] = {8, 9, 62, 63, 64, 65, 128, 15000};
    for (size_t d = 0; d < sizeof(distances) / sizeof(distances[0]); d++) {
        memset(text, 'x', sizeof(text));
        for (size_t pos = 0; pos <= 1024; pos += 16)
            memcpy(text + pos, "UTXOs in", 8);
        text[1024 + distances[d]] = 'U';
        FILE *f = text_file(text, sizeof(text));
        searches = 0;
        CHECK(snapshot_log_match(f, sizeof(text)) == 1024);
        printf("candidate_distance=%zu substring_searches=%zu\n", distances[d], searches);
        if (!baseline && distances[d] < 64) CHECK(searches == 0);
        CHECK(fclose(f) == 0);
    }
    /* Dense false candidates retain bulk search instead of a full scalar walk. */
    memset(text, 'U', sizeof(text));
    for (int valid = 0; valid < 2; valid++) {
        if (valid) memcpy(text, "UTXOs in", 8);
        FILE *f = text_file(text, sizeof(text));
        searches = 0;
        CHECK(snapshot_log_match(f, sizeof(text)) == (valid ? 0 : -1));
        CHECK(searches <= 2);
        CHECK(fclose(f) == 0);
    }
    memset(text, 'x', sizeof(text));
    for (size_t pos = 0; pos < sizeof(text); pos += 16)
        memcpy(text + pos, "UTXOs in", 8);
    text[sizeof(text) - 1] = 'U';
    FILE *f = text_file(text, sizeof(text));
    for (int trial = 0; trial < 3; trial++) {
        searches = 0;
        double start = now();
        for (int repeat = 0; repeat < 2000; repeat++)
            CHECK(snapshot_log_match(f, sizeof(text)) == (off_t)sizeof(text) - 16);
        printf("trial=%d scans=2000 bytes_per_scan=%zu substring_searches=%zu seconds=%.6f\n",
               trial + 1, sizeof(text), searches, now() - start);
        if (!baseline) CHECK(searches == 0);
    }
    CHECK(fclose(f) == 0);
    puts(baseline ? "BASELINE: suffix lookup measured" :
         "PASS: latest match, reverse-window boundaries, dense fallback, suffix work budget");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$baseline"
