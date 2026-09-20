#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Phase observer benchmark: text, sparse/paired NULs, and mixed/dense binary input.
# Usage: bash tools/scripts/bench_fresh_sync_nul_scan_selftest.sh [--analyze] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
analyze=0
if [[ ${1:-} == --analyze ]]; then analyze=1; shift; fi
source_file=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/zcl-phase-nul-scan.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
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
C
awk '/^enum log_phase / { copy = 1 }
     /^\/\* Check if HTTPS/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
int main(void)
{
    /* Exact byte preservation and window boundaries, including empty input,
     * short final windows and NULs separated by 63, 64 and 65 bytes. Guards
     * must remain unchanged even when they contain a NUL themselves. */
    for (size_t length = 0; length <= 160; length++) {
        for (size_t gap = 1; gap <= 129; gap++) {
            char actual[162], expected[162];
            for (size_t i = 0; i < sizeof(actual); i++)
                actual[i] = i % gap == 0 ? '\0' : (char)(i + 64);
            memcpy(expected, actual, sizeof(actual));
            for (size_t i = 1; i <= length; i++)
                if (expected[i] == '\0') expected[i] = '\n';
            phase_log_normalize(actual + 1, length);
            CHECK(memcmp(actual, expected, sizeof(actual)) == 0);
        }
    }
    /* Full windows at every alignment, arbitrary high-bit bytes and a short
     * suffix. Compare the complete allocation so vector stores cannot silently
     * change guards or adjacent text. */
    for (size_t offset = 0; offset < 64; offset++) {
        char actual[4096 + 128], expected[sizeof(actual)];
        for (size_t i = 0; i < sizeof(actual); i++)
            actual[i] = i % 3 == 0 ? '\0' : (char)(i * 37);
        memcpy(expected, actual, sizeof(actual));
        size_t length = 4096 + offset;
        for (size_t i = offset; i < offset + length; i++)
            if (expected[i] == '\0') expected[i] = '\n';
        phase_log_normalize(actual + offset, length);
        CHECK(memcmp(actual, expected, sizeof(actual)) == 0);
    }
    const size_t extent = 16 * 1024 * 1024;
    for (int mode = 0; mode < 6; mode++) {
        FILE *f = tmpfile();
        CHECK(f != NULL);
        char block[4096];
        memset(block, mode == 2 ? 0 : 'x', sizeof(block));
        if (mode == 1) block[0] = '\0';
        /* Two sparse NULs must not select a scalar walk of the entire
         * text suffix merely because their distance is one window. */
        if (mode == 3) block[0] = block[64] = '\0';
        if (mode >= 4) {
            size_t gap = mode == 4 ? 65 : 2;
            for (size_t i = 0; i < sizeof(block); i += gap) block[i] = '\0';
        }
        for (size_t pos = 0; pos < extent; pos += sizeof(block))
            CHECK(fwrite(block, 1, sizeof(block), f) == sizeof(block));
        /* A real marker after all padding must survive every input shape.
         * Other absent milestones ensure the complete extent is scanned. */
        const char *marker = phase_markers[LOG_FLYCLIENT];
        CHECK(fseeko(f, (off_t)(extent - strlen(marker)), SEEK_SET) == 0);
        CHECK(fputs(marker, f) >= 0 && fflush(f) == 0);
        int64_t start = platform_time_monotonic_us();
        for (int repeat = 0; repeat < 20; repeat++) {
            struct phase_log log = {0};
            CHECK(phase_log_poll(f, &log));
            CHECK(log.offset == (off_t)extent);
            for (int phase = 0; phase < LOG_PHASE_COUNT; phase++)
                CHECK(log.seen[phase] == (phase == LOG_FLYCLIENT));
        }
        double seconds = (double)(platform_time_monotonic_us() - start) / 1000000;
        printf("mode=%s scans=20 bytes=%zu seconds=%.6f\n",
               mode == 0 ? "text" : mode == 1 ? "sparse" :
               mode == 2 ? "dense" : mode == 3 ? "paired" :
               mode == 4 ? "window-gaps" : "alternating", extent, seconds);
        CHECK(fclose(f) == 0);
    }
    puts("PASS: full extent scanned and only the real milestone observed");
    return 0;
}
C
includes=(-I"$root/platform/modules/platform/include"
          -I"$root/platform/modules/base/include" -I"$root/platform/modules/util/include")
"${CC:-cc}" -std=c23 -D_DEFAULT_SOURCE -O2 -Wall -Wextra -Werror \
    "${includes[@]}" "$fixture/test.c" "$root/platform/modules/platform/src/clock.c" \
    "$root/platform/modules/base/src/log_level.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" -std=c23 -D_DEFAULT_SOURCE -Wall -Wextra -Werror -fanalyzer \
        "${includes[@]}" -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test"
