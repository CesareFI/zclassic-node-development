#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Snapshot-summary behavior and observer work on local text logs; no node.
# Usage: bash tools/scripts/bench_fresh_sync_summary_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=0
analyze=0
while [[ ${1:-} == --* ]]; do
    case $1 in
        --baseline) baseline=1 ;;
        --analyze) analyze=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
SOURCE=${1:-$ROOT/tools/bench_fresh_sync.c}
TMP=$(mktemp -d /tmp/zcl-snapshot-summary.XXXXXX)
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
static size_t bytes, commands;
static size_t reads, fail_at;
static bool short_read;
size_t counted_read(void *out, size_t size, size_t count, FILE *f)
{
    reads++;
    if (short_read || (fail_at && reads == fail_at)) return 0;
    size_t n = fread(out, size, count, f);
    bytes += n * size;
    return n;
}
FILE *counted_open(const char *cmd, const char *mode)
{
    commands++;
    return popen(cmd, mode);
}
#define fread counted_read
#define popen counted_open
C
awk '/^static off_t snapshot_log_(chunk|match)\(/ { copy = 1 }
     /^\/\* Startup progress/ { copy = 0 }
     /^static int run_cmd\(/ { copy = 1; sub(/^static /, "") }
     /^\/\* RPC call/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
#undef fread
#undef popen
static void observe(const char *logfile, const char *expected)
{
C
awk '/^        if \(t_snap_end == 0/ { scope = 1 }
     scope && /char line\[256\]/ { copy = 1 }
     copy && /^[[:space:]]*printf\(/ { exit }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
    CHECK(strcmp(line, expected) == 0);
}
static void fixture(const char *path, const char *text, const char *expected)
{
    FILE *f = fopen(path, "w");
    CHECK(f != NULL);
    CHECK(fputs(text, f) >= 0);
    CHECK(fclose(f) == 0);
    observe(path, expected);
}
int main(int argc, char **argv)
{
    CHECK(argc == 3);
    bool baseline = strcmp(argv[2], "1") == 0;
    const char *path = argv[1];
    fixture(path, "", "");
    fixture(path, "\nnoise\n", "");
    fixture(path, "12 UTXOs in 2s", "12 UTXOs in 2s");
    fixture(path, "12 UTXOs in 2s\n\nnoise\n", "12 UTXOs in 2s");
    fixture(path, "1 UTXOs in 3s\n2 UTXOs in 4s\r\nnoise", "2 UTXOs in 4s\r");
    fixture(path, "UTXO\ns in\n", "");
    fixture(path, "UTXOs inn\n", "UTXOs inn");
    FILE *binary = fopen(path, "w");
    CHECK(binary != NULL);
    CHECK(fputs("12 UTXOs in 2s", binary) >= 0);
    CHECK(fputc('\0', binary) != EOF);
    CHECK(fclose(binary) == 0);
    observe(path, "");
    char longline[16384];
    memset(longline, 'x', sizeof(longline));
    memcpy(longline, "UTXOs in", 8);
    longline[254] = '\0';
    fixture(path, longline, longline);
    longline[254] = 'x'; longline[255] = '\0';
    fixture(path, longline, "");
    longline[255] = 'x'; longline[sizeof(longline) - 1] = '\0';
    fixture(path, longline, "");
    FILE *oversized = fopen(path, "w");
    CHECK(oversized != NULL);
    CHECK(fputs("old UTXOs in 1s\n", oversized) >= 0);
    CHECK(fputs(longline, oversized) >= 0);
    CHECK(fclose(oversized) == 0);
    observe(path, ""); /* Never fall back from an oversized latest match. */
    /* Marker and newline at every read-boundary split. A long nonmatching
     * final line must not hide the preceding summary or join two lines. */
    for (size_t suffix = 16360; suffix < 16410; suffix++) {
        FILE *f = fopen(path, "w");
        CHECK(f != NULL);
        CHECK(fputs("old UTXOs in 1s\nlatest UTXOs in 2s\n", f) >= 0);
        for (size_t i = 0; i < suffix; i++) CHECK(fputc('x', f) != EOF);
        CHECK(fclose(f) == 0);
        observe(path, "latest UTXOs in 2s");
    }
    /* 64 MiB real text log, useful summary near the end, warm page cache. */
    FILE *f = fopen(path, "w");
    CHECK(f != NULL);
    char block[4096];
    memset(block, 'x', sizeof(block)); block[sizeof(block) - 1] = '\n';
    for (int i = 0; i < 16384; i++)
        CHECK(fwrite(block, 1, sizeof(block), f) == sizeof(block));
    CHECK(fputs("123 UTXOs in 4s\nnoise\n", f) >= 0);
    CHECK(fclose(f) == 0);
    observe(path, "123 UTXOs in 4s");
    for (int run = 0; run < 3; run++) {
        bytes = commands = 0;
        struct timespec begin, end;
        CHECK(clock_gettime(CLOCK_MONOTONIC, &begin) == 0);
        for (int i = 0; i < 10; i++) observe(path, "123 UTXOs in 4s");
        CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
        printf("run=%d polls=10 log_mib=64 direct_read_bytes=%zu commands=%zu seconds=%.6f\n",
               run, bytes, commands, (double)(end.tv_sec - begin.tv_sec) +
               (double)(end.tv_nsec - begin.tv_nsec) / 1e9);
        if (!baseline) CHECK(commands == 0 && bytes <= 10 * (16384 + 512));
    }
    if (!baseline) {
        short_read = true;
        observe(path, "");
        short_read = false;
        reads = 0; fail_at = 2;
        observe(path, ""); /* Failure while recovering the matching line. */
        fail_at = 0;
    }
    CHECK(truncate(path, 64 * 1024 * 1024) == 0);
    struct timespec begin, end;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &begin) == 0);
    observe(path, "");
    CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
    printf("absent_summary polls=1 log_mib=64 seconds=%.6f\n",
           (double)(end.tv_sec - begin.tv_sec) +
           (double)(end.tv_nsec - begin.tv_nsec) / 1e9);
    CHECK(unlink(path) == 0);
    observe(path, "");
    puts("PASS: latest text summary, boundaries, oversized lines, missing/read failure, bounded tail work");
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L)
"${CC:-cc}" "${flags[@]}" -O2 "$TMP/test.c" -o "$TMP/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
timeout 30 "$TMP/test" "$TMP/node.log" "$baseline"
