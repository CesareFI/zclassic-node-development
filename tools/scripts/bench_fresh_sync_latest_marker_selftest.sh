#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Latest snapshot-summary lookup cost; isolated text fixtures, no node/RPC.
# Usage: bash tools/scripts/bench_fresh_sync_latest_marker_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
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
fixture=$(mktemp -d /tmp/zcl-latest-marker.XXXXXX)
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
awk '/^static off_t snapshot_log_(chunk|match)\(/ { copy = 1 }
     /^\/\* A displayable line/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef strstr
static double now(void)
{
    struct timespec ts;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
static FILE *text_file(const char *text, size_t length)
{
    FILE *f = tmpfile();
    CHECK(f != NULL);
    CHECK(setvbuf(f, NULL, _IONBF, 0) == 0);
    CHECK(fwrite(text, 1, length, f) == length);
    return f;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    const char *cases[] = {
        "", "U", "UTXOs i", "UTXOs in", "UTXOs in U",
        "UTXOs in UT", "UTXOs in UTXOs i", "UTXOs in\nUTXOs in",
        "UTXOs in UTXOs in U unrelated", "UTXOs IN", "UUUUUTXOs inU"
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        const char *text = cases[i];
        off_t expected = -1;
        for (const char *p = strstr(text, "UTXOs in"); p;
             p = strstr(p + 1, "UTXOs in")) expected = (off_t)(p - text);
        FILE *f = text_file(text, strlen(text));
        CHECK(snapshot_log_match(f, (off_t)strlen(text)) == expected);
        CHECK(fclose(f) == 0);
    }
    /* Include absent, recent, early and repeated summaries, plus fallback
     * after a later unrelated candidate. These are warm observer costs. */
    for (int mode = 0; mode < 5; mode++) {
        char text[16384];
        memset(text, 'x', sizeof(text));
        off_t expected = -1;
        if (mode == 1) expected = sizeof(text) - 8;
        if (mode == 2) expected = 0;
        if (mode == 3 || mode == 4) {
            for (size_t i = 0; i < sizeof(text); i += 16)
                memcpy(text + i, "UTXOs in", 8);
            expected = sizeof(text) - 16;
        }
        if (expected >= 0) memcpy(text + expected, "UTXOs in", 8);
        if (mode == 4) text[sizeof(text) - 1] = 'U';
        FILE *f = text_file(text, sizeof(text));
        for (int run = 0; run < 3; run++) {
            searches = 0;
            double start = now();
            for (int repeat = 0; repeat < 2000; repeat++)
                CHECK(snapshot_log_match(f, sizeof(text)) == expected);
            printf("mode=%d run=%d scans=2000 bytes_per_scan=%zu substring_searches=%zu seconds=%.6f\n",
                   mode, run + 1, sizeof(text), searches, now() - start);
            if (!baseline && mode < 4) CHECK(searches == 0);
        }
        CHECK(fclose(f) == 0);
    }
    puts("PASS: latest offsets, incomplete candidates, unrelated suffixes and lookup budget");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$baseline"
