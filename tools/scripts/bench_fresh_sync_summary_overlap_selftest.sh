#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Snapshot-summary overlap I/O on isolated warm-cache text logs; no node.
# Usage: bash tools/scripts/bench_fresh_sync_summary_overlap_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d /tmp/zcl-summary-overlap.XXXXXX)
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
awk '/^static off_t snapshot_log_(bisect|chunk|match)\(/ { copy = 1 }
     /^\/\* A displayable line/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef fread
static long long read_calls(void)
{
    FILE *f = fopen("/proc/self/io", "r");
    if (!f) return -1;
    char line[128];
    long long count = -1;
    while (fgets(line, sizeof(line), f))
        if (sscanf(line, "syscr: %lld", &count) == 1) break;
    CHECK(fclose(f) == 0);
    return count;
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
    const off_t extent = 16 * 1024 * 1024;
    FILE *f = tmpfile();
    CHECK(f != NULL);
    char block[16384];
    memset(block, 'x', sizeof(block));
    for (off_t at = 0; at < extent; at += (off_t)sizeof(block))
        CHECK(fwrite(block, 1, sizeof(block), f) == sizeof(block));
    CHECK(fflush(f) == 0);
    for (int run = 0; run < 3; run++) {
        bytes = 0;
        long long before = read_calls();
        double start = now();
        for (int repeat = 0; repeat < 20; repeat++)
            CHECK(snapshot_log_match(f, extent) == -1);
        double elapsed = now() - start;
        long long after = read_calls();
        printf("run=%d scans=20 log_mib=16 read_bytes=%zu read_syscalls=%lld seconds=%.6f\n",
               run + 1, bytes, before < 0 || after < 0 ? -1 : after - before, elapsed);
        if (!baseline) CHECK(bytes == 20 * (size_t)extent);
    }
    CHECK(fclose(f) == 0);
    /* Every marker split, including a final short reverse chunk. */
    for (size_t prefix = 0; prefix < 9; prefix++) {
        f = tmpfile();
        CHECK(f != NULL);
        CHECK(fwrite(block, 1, prefix, f) == prefix);
        CHECK(fputs("UTXOs in", f) >= 0);
        CHECK(fwrite(block, 1, sizeof(block), f) == sizeof(block));
        CHECK(fflush(f) == 0);
        for (off_t end = 16385; end <= 16392; end++)
            CHECK(snapshot_log_match(f, end) == (off_t)prefix);
        CHECK(fclose(f) == 0);
    }
    puts(baseline ? "BASELINE: overlap read cost measured" :
         "PASS: no overlap rereads, all marker splits and short reverse chunks");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$baseline"
