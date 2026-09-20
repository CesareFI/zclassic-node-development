#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure the complete summary reader, including stdio seek/read-ahead.
# Usage: bash tools/scripts/bench_fresh_sync_summary_io_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-summary-io.XXXXXX")
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
C
awk '/^static off_t snapshot_log_(chunk|match)\(/ { if (!copy) starts++; copy = 1 }
     /^\/\* Startup progress/ { copy = 0; ends++ }
     copy { print }
     END { if (starts != 1 || ends != 1) exit 1 }' \
    "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
static bool read_bytes(unsigned long long *value)
{
    FILE *f = fopen("/proc/self/io", "r");
    if (!f) return false;
    bool ok = fscanf(f, "rchar: %llu", value) == 1;
    CHECK(fclose(f) == 0);
    return ok;
}
static double now(void)
{
    struct timespec ts;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
int main(int argc, char **argv)
{
    CHECK(argc == 3);
    bool baseline = strcmp(argv[2], "1") == 0, budget_ok = true;
    const size_t extents[] = {4194304, 4194305, 4198399};
    static const char summary[] = "1 UTXOs in 0.1s\n";
    char block[16384], line[256];
    memset(block, 'x', sizeof(block));
    block[sizeof(block) - 1] = '\n';
    for (size_t i = 0; i < sizeof(extents) / sizeof(extents[0]); i++) {
        FILE *f = fopen(argv[1], "wb");
        CHECK(f != NULL);
        CHECK(fwrite(summary, 1, sizeof(summary) - 1, f) == sizeof(summary) - 1);
        for (size_t at = sizeof(summary) - 1; at < extents[i]; ) {
            size_t n = extents[i] - at;
            if (n > sizeof(block)) n = sizeof(block);
            CHECK(fwrite(block, 1, n, f) == n);
            at += n;
        }
        CHECK(fclose(f) == 0);
        for (int trial = 0; trial < 3; trial++) {
            unsigned long long before = 0, after = 0;
            bool measured = read_bytes(&before);
            double start = now();
            for (int repeat = 0; repeat < 20; repeat++) {
                snapshot_log_summary(argv[1], line, sizeof(line));
                CHECK(strcmp(line, "1 UTXOs in 0.1s") == 0);
            }
            double elapsed = now() - start;
            measured = read_bytes(&after) && measured;
            printf("extent=%zu trial=%d scans=20 seconds=%.6f",
                   extents[i], trial + 1, elapsed);
            if (measured) {
                /* One reverse pass, a 512-byte line window per scan, and
                 * allowance for the /proc accounting read itself. */
                unsigned long long budget = 20 * (extents[i] + 512) + 4096;
                printf(" read_bytes=%llu budget=%llu\n", after - before, budget);
                if (after < before || after - before > budget) budget_ok = false;
            } else {
                puts(" read_budget=UNOBSERVED (/proc/self/io unavailable)");
            }
        }
    }
    CHECK(unlink(argv[1]) == 0);
    if (!baseline) CHECK(budget_ok);
    puts(baseline ? "BASELINE: summary I/O measured" :
         "PASS: exact summaries and available kernel read-byte budgets");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$fixture/node.log" "$baseline"
