#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Bound binary-log normalization work without changing any observed bytes.
# Usage: bash tools/scripts/bench_fresh_sync_normalize_window_selftest.sh [--analyze] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
analyze=0
if [[ ${1:-} == --analyze ]]; then analyze=1; shift; fi
source_file=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/zcl-normalize-window.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static size_t searches;
static void *counted_memchr(const void *buf, int value, size_t size)
{
    searches++;
    return memchr(buf, value, size);
}
#define memchr counted_memchr
C
awk '/^static void phase_log_normalize\(/ { copy = 1 }
     /^static bool phase_log_scan_chunk\(|^static bool phase_log_poll\(/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef memchr
int main(void)
{
    const size_t gaps[] = {1, 2, 63, 64, 65, 127, 128, 129, 255, 256, 257};
    /* Compare every byte, including both guards. Cover short windows, every
     * alignment, high-bit text, and NULs around old and new window edges. */
    for (size_t length = 0; length <= 1024; length++) {
        for (size_t gap = 0; gap < sizeof(gaps) / sizeof(gaps[0]); gap++) {
            char actual[1152], expected[sizeof(actual)];
            size_t offset = length % 64 + 1;
            for (size_t i = 0; i < sizeof(actual); i++)
                actual[i] = i % gaps[gap] == 0 ? '\0' : (char)(i * 37);
            memcpy(expected, actual, sizeof(actual));
            for (size_t i = offset; i < offset + length; i++)
                if (expected[i] == '\0') expected[i] = '\n';
            phase_log_normalize(actual + offset, length);
            CHECK(memcmp(actual, expected, sizeof(actual)) == 0);
        }
    }
    char block[65536];
    memset(block, 'x', sizeof(block));
    searches = 0;
    phase_log_normalize(block, sizeof(block));
    CHECK(searches == 1); /* Ordinary text retains its single search. */
    for (size_t i = 0; i < sizeof(block); i += 65) block[i] = '\0';
    searches = 0;
    phase_log_normalize(block, sizeof(block));
    for (size_t i = 0; i < sizeof(block); i++)
        CHECK(block[i] == (i % 65 == 0 ? '\n' : 'x'));
    printf("mixed bytes=%zu gap=65 searches=%zu\n", sizeof(block), searches);
    /* Gate work rather than elapsed time: a short-window loop searches once
     * per NUL here. Batched replacement must at least halve that overhead. */
    CHECK(searches <= sizeof(block) / 128 + 2);
    puts("PASS: exact normalization, guarded boundaries, bounded search work");
    return 0;
}
C
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" -std=c23 -Wall -Wextra -Werror -fanalyzer \
        -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
"$fixture/test"
