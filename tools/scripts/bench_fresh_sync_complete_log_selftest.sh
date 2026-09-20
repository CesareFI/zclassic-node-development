#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Measure actual phase-reader work after all startup milestones are present.
# Usage: bash tools/scripts/bench_fresh_sync_complete_log_selftest.sh [--measure] [--analyze] [source.c]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
measure=0
analyze=false
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --measure) measure=1 ;;
        --analyze) analyze=true ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
SOURCE="${1:-$ROOT/tools/bench_fresh_sync.c}"
TMP="$(mktemp -d /tmp/zcl-phase-complete.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
#include "platform/time_compat.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <unistd.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static size_t read_bytes, read_calls;
static size_t counted_read(void *buf, size_t size, size_t count, FILE *f)
{
    size_t n = fread(buf, size, count, f);
    read_bytes += n * size;
    read_calls++;
    return n;
}
#define fread counted_read
C
awk '/^enum log_phase / { copy = 1 }
     /^\/\* Check if HTTPS/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
#undef fread
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    const bool measure = strcmp(argv[1], "1") == 0;
    const size_t log_size = 32 * 1024 * 1024;
    char block[4096];
    memset(block, 'x', sizeof(block));
    FILE *f = tmpfile();
    CHECK(f != NULL);
    /* mode 0: all markers in first read; mode 1: last marker spans reads;
     * mode 2: last marker absent; mode 3: last marker at the end of the log. */
    for (int mode = 0; mode < 4; mode++) {
        rewind(f);
        for (size_t n = 0; n < log_size; n += sizeof(block))
            CHECK(fwrite(block, 1, sizeof(block), f) == sizeof(block));
        rewind(f);
        for (int phase = 0; phase < LOG_PHASE_COUNT - 1; phase++)
            CHECK(fprintf(f, "%s\n", phase_markers[phase]) > 0);
        const char *last = phase_markers[LOG_PHASE_COUNT - 1];
        if (mode == 1) CHECK(fseeko(f, 4090, SEEK_SET) == 0);
        if (mode == 3)
            CHECK(fseeko(f, (off_t)(log_size - strlen(last)), SEEK_SET) == 0);
        if (mode != 2) CHECK(fputs(last, f) >= 0);
        CHECK(fflush(f) == 0);
        read_bytes = read_calls = 0;
        int64_t begin = platform_time_monotonic_us();
        for (int repeat = 0; repeat < 10; repeat++) {
            struct phase_log log = {0};
            CHECK(phase_log_poll(f, &log));
            /* Late/absent milestones require the complete history, now
             * spread across bounded turns. Keep the total-work assertion. */
            while (mode >= 2 && log.offset < (off_t)log_size) {
                off_t before = log.offset;
                CHECK(phase_log_poll(f, &log));
                CHECK(log.offset > before);
            }
            for (int phase = 0; phase < LOG_PHASE_COUNT; phase++)
                CHECK(log.seen[phase] == (mode != 2 || phase != LOG_PHASE_COUNT - 1));
            CHECK(log.offset == (off_t)(read_bytes / (size_t)(repeat + 1)));
        }
        int64_t elapsed = platform_time_monotonic_us() - begin;
        printf("mode=%d scans=10 log_bytes=%zu read_bytes=%zu read_calls=%zu seconds=%.6f\n",
               mode, log_size, read_bytes, read_calls, (double)elapsed / 1000000.0);
        if (mode >= 2) {
            CHECK(read_bytes == 10 * log_size);
            /* Two initial small reads, then bulk reads, within each of
             * two 16 MiB turns. Keep this a work budget, not a time gate. */
            if (!measure) CHECK(read_calls <= 10 * 2 * (2 + 256));
        }
        else if (!measure) CHECK(read_bytes == (size_t)(mode + 1) * 4096 * 10);
    }
    /* Exercise every possible marker split at the small-to-bulk transition
     * and between bulk reads. A sparse fixture also exercises NUL handling. */
    const off_t boundaries[] = {8192, 8192 + 65536};
    for (size_t b = 0; b < sizeof(boundaries) / sizeof(boundaries[0]); b++) {
        for (int phase = 0; phase < LOG_PHASE_COUNT; phase++) {
            const char *marker = phase_markers[phase];
            for (size_t split = 1; split < strlen(marker); split++) {
                CHECK(ftruncate(fileno(f), 0) == 0);
                CHECK(fseeko(f, boundaries[b] - (off_t)split, SEEK_SET) == 0);
                CHECK(fputs(marker, f) >= 0 && fflush(f) == 0);
                struct phase_log log = {0};
                CHECK(phase_log_poll(f, &log));
                CHECK(log.offset == boundaries[b] + (off_t)(strlen(marker) - split));
                for (int i = 0; i < LOG_PHASE_COUNT; i++)
                    CHECK(log.seen[i] == (i == phase));
            }
        }
    }
    CHECK(fclose(f) == 0);
    puts("PASS: milestones, early completion, bulk-read budget, every marker split at bulk boundaries");
    return 0;
}
C
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror -D_DEFAULT_SOURCE \
    -I"$ROOT/platform/modules/platform/include" \
    -I"$ROOT/platform/modules/base/include" -I"$ROOT/platform/modules/util/include" \
    "$TMP/test.c" "$ROOT/platform/modules/platform/src/clock.c" \
    "$ROOT/platform/modules/base/src/log_level.c" -o "$TMP/test"
if "$analyze"; then
    "${CC:-cc}" -std=c23 -Wall -Wextra -Werror -fanalyzer -D_DEFAULT_SOURCE \
        -I"$ROOT/platform/modules/platform/include" \
        -I"$ROOT/platform/modules/base/include" -I"$ROOT/platform/modules/util/include" \
        -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
timeout 30 "$TMP/test" "$measure"
