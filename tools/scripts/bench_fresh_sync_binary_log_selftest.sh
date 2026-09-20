#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise binary-byte normalization in the real phase scanner, without a node.
# Usage: bash tools/scripts/bench_fresh_sync_binary_log_selftest.sh [--analyze] [source.c]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
analyze=false
if [ "${1:-}" = --analyze ]; then analyze=true; shift; fi
SOURCE="${1:-$ROOT/tools/bench_fresh_sync.c}"
TMP="$(mktemp -d /tmp/zcl-binary-log.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
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
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
static void scan(const void *data, size_t n, int expected)
{
    FILE *f = tmpfile();
    CHECK(f != NULL);
    CHECK(fwrite(data, 1, n, f) == n);
    CHECK(fflush(f) == 0);
    struct phase_log log = {0};
    CHECK(phase_log_poll(f, &log));
    for (int phase = 0; phase < LOG_PHASE_COUNT; phase++)
        CHECK(log.seen[phase] == (phase == expected));
    CHECK(fclose(f) == 0);
}
int main(void)
{
    char data[8192];
    /* Every byte value, including all-NUL input, followed by a real marker
     * across a read boundary. High-bit bytes must retain their positions. */
    for (int byte = 0; byte <= 255; byte++) {
        for (int phase = 0; phase < LOG_PHASE_COUNT; phase++) {
            memset(data, byte, sizeof(data));
            memcpy(data + 4090, phase_markers[phase], strlen(phase_markers[phase]));
            scan(data, sizeof(data), phase);
        }
    }
    /* A NUL at any position in the first block must not hide a later marker. */
    for (size_t pos = 0; pos < 4096; pos++) {
        memset(data, 'x', sizeof(data));
        data[pos] = '\0';
        memcpy(data + 4096, phase_markers[0], strlen(phase_markers[0]));
        scan(data, sizeof(data), 0);
    }
    /* Replacing a NUL must never concatenate marker fragments, either in
     * one read or in the overlap retained between two reads. */
    for (int phase = 0; phase < LOG_PHASE_COUNT; phase++) {
        const char *marker = phase_markers[phase];
        size_t len = strlen(marker);
        for (size_t split = 1; split < len; split++) {
            for (int boundary = 0; boundary <= 1; boundary++) {
                memset(data, 'x', sizeof(data));
                size_t start = boundary ? 4096 - split : 0;
                memcpy(data + start, marker, split);
                data[start + split] = '\0';
                memcpy(data + start + split + 1, marker + split, len - split);
                scan(data, sizeof(data), -1);
            }
        }
    }
    memset(data, 0, sizeof(data));
    scan(data, sizeof(data), -1);
    puts("PASS: all byte values, every NUL offset, dense NULs, split markers, no concatenation");
    return 0;
}
C
"${CC:-cc}" -std=c23 -D_DEFAULT_SOURCE -O2 -Wall -Wextra -Werror -pedantic \
    "$TMP/test.c" -o "$TMP/test"
if "$analyze"; then
    "${CC:-cc}" -std=c23 -D_DEFAULT_SOURCE -Wall -Wextra -Werror -fanalyzer \
        -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
timeout 30 "$TMP/test"
