#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Bound absent snapshot-summary work; isolated text fixtures, no node or RPC.
# Usage: bash tools/scripts/bench_fresh_sync_summary_budget_selftest.sh [--baseline] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
source_file=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/zcl-summary-budget.XXXXXX)
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
static size_t bytes;
static size_t counted_read(void *buf, size_t size, size_t count, FILE *f)
{
    size_t n = fread(buf, size, count, f);
    bytes += size * n;
    return n;
}
#define fread counted_read
C
awk '/^static off_t snapshot_log_(chunk|match)\(/ { copy = 1 }
     /^\/\* A displayable line/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef fread
static double now(void)
{
    struct timespec ts;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
static void write_at(FILE *f, off_t offset, const char *text)
{
    CHECK(fseeko(f, offset, SEEK_SET) == 0);
    CHECK(fputs(text, f) >= 0);
    CHECK(fflush(f) == 0);
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    const off_t budget = 16 * 1024 * 1024;
    const off_t extent = 256 * 1024 * 1024;
    /* Real text, not sparse NULs that trigger the binary-log refusal. */
    FILE *f = tmpfile();
    CHECK(f != NULL);
    char block[16384];
    memset(block, 'x', sizeof(block));
    block[sizeof(block) - 1] = '\n';
    for (off_t at = 0; at < extent; at += (off_t)sizeof(block))
        CHECK(fwrite(block, 1, sizeof(block), f) == sizeof(block));
    CHECK(fflush(f) == 0);
    for (int run = 0; run < 3; run++) {
        bytes = 0;
        double start = now();
        CHECK(snapshot_log_match(f, extent) == -1);
        printf("run=%d log_mib=256 read_bytes=%zu seconds=%.6f\n",
               run + 1, bytes, now() - start);
        /* Seven overlap bytes per chunk, all still inside the window. */
        if (!baseline) CHECK(bytes <= (size_t)budget + 7 * 1023);
    }
    if (!baseline) {
        off_t floor = extent - budget;
        write_at(f, floor - 1, "UTXOs in");
        CHECK(snapshot_log_match(f, extent) == -1);
        write_at(f, floor - 1, "xxxxxxxx");
        write_at(f, floor, "UTXOs in");
        CHECK(snapshot_log_match(f, extent) == floor);
        write_at(f, extent - 16387, "UTXOs in");
        CHECK(snapshot_log_match(f, extent) == extent - 16387);
        write_at(f, extent - 8, "UTXOs in");
        CHECK(snapshot_log_match(f, extent) == extent - 8);
        /* A window-sized or smaller log still searches all its bytes. */
        write_at(f, 0, "UTXOs in");
        CHECK(snapshot_log_match(f, budget) == 0);
        CHECK(snapshot_log_match(f, 8) == 0);
        CHECK(snapshot_log_match(f, 0) == -1);
    }
    CHECK(fclose(f) == 0);
    puts(baseline ? "BASELINE: absent-summary cost measured; budget not enforced" :
         "PASS: absent-summary work budget, window boundary, split/latest matches, short logs");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if [[ ${ANALYZE:-0} == 1 ]]; then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
"$fixture/test" "$baseline"
