#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Startup-tail read amplification regression; isolated logs, no node or network.
# Usage: bash tools/scripts/bench_fresh_sync_tail_io_selftest.sh [--analyze] [source.c]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
analyze=0
if [[ ${1:-} == --analyze ]]; then analyze=1; shift; fi
SOURCE=${1:-$ROOT/tools/bench_fresh_sync.c}
TMP=$(mktemp -d /tmp/zcl-tail-io.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
C
awk '/^static void startup_log_tail\(/ { copy = 1 }
     /^\/\* Capture complete/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
/* Kernel-returned bytes include stdio seek/read-ahead, unlike a wrapper
 * around fread. Optional on other hosts; value checks always run. */
static bool read_bytes(unsigned long long *value)
{
    FILE *f = fopen("/proc/self/io", "r");
    if (!f) return false;
    bool ok = fscanf(f, "rchar: %llu", value) == 1;
    CHECK(fclose(f) == 0);
    return ok;
}

static void write_fixture(const char *path, size_t extent)
{
    static const char ending[] = "\nprogress\n";
    FILE *f = fopen(path, "wb");
    CHECK(f != NULL);
    CHECK(extent >= sizeof(ending) - 1);
    CHECK(fseeko(f, (off_t)(extent - (sizeof(ending) - 1)), SEEK_SET) == 0);
    CHECK(fwrite(ending, 1, sizeof(ending) - 1, f) == sizeof(ending) - 1);
    CHECK(fclose(f) == 0);
}

int main(int argc, char **argv)
{
    CHECK(argc == 2);
    char line[256];
    /* Straddle stdio/page boundaries and exercise a tail shorter than the
     * caller's buffer. Sparse prefixes isolate observation cost from writes. */
    const size_t extents[] = {10, 255, 256, 257, 4095, 4096, 4097,
                             67108864, 67112959};
    for (size_t i = 0; i < sizeof(extents) / sizeof(extents[0]); i++) {
        write_fixture(argv[1], extents[i]);
        startup_log_tail(argv[1], line, sizeof(line));
        CHECK(strcmp(line, "progress\n") == 0);
    }
    bool budget_ok = true;
    for (int trial = 0; trial < 3; trial++) {
        struct timespec begin, end;
        unsigned long long before = 0, after = 0;
        bool measured = read_bytes(&before);
        CHECK(clock_gettime(CLOCK_MONOTONIC, &begin) == 0);
        for (int i = 0; i < 3000; i++) {
            startup_log_tail(argv[1], line, sizeof(line));
            CHECK(strcmp(line, "progress\n") == 0);
        }
        CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
        measured = read_bytes(&after) && measured;
        printf("trial=%d observations=3000 wall_ms=%.3f", trial + 1,
               (double)(end.tv_sec - begin.tv_sec) * 1000.0 +
               (double)(end.tv_nsec - begin.tv_nsec) / 1e6);
        if (measured) {
            /* 256 bytes per observation plus the /proc accounting read. */
            const unsigned long long budget = 3000 * sizeof(line) + 4096;
            printf(" read_bytes=%llu budget=%llu\n", after - before, budget);
            if (after < before || after - before > budget) budget_ok = false;
        } else {
            puts(" read_budget=UNOBSERVED (/proc/self/io unavailable)");
        }
    }
    CHECK(budget_ok);
    CHECK(unlink(argv[1]) == 0);
    puts("PASS: startup-tail boundaries and available kernel read-byte budget");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L)
"${CC:-cc}" "${flags[@]}" -O2 "$TMP/test.c" -o "$TMP/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
timeout 15 "$TMP/test" "$TMP/node.log"
