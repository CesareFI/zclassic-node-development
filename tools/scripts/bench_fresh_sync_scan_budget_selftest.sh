#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Bound one observer turn without dropping unread phase evidence. No node.
# Usage: bash tools/scripts/bench_fresh_sync_scan_budget_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d /tmp/zcl-phase-budget.XXXXXX)
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
    bytes += n * size;
    return n;
}
#define fread counted_read
C
awk '/^enum log_phase / { copy = 1 }
     /^\/\* Check if HTTPS/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef fread
static double now(void)
{
    struct timespec ts;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
static void poll(FILE *f, struct phase_log *log, bool baseline)
{
    bytes = 0;
    CHECK(phase_log_poll(f, log));
    if (!baseline) CHECK(bytes <= 16 * 1024 * 1024);
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    const bool baseline = strcmp(argv[1], "1") == 0;
    const off_t budget = 16 * 1024 * 1024;
    const off_t extent = 4 * budget;
    FILE *f = tmpfile();
    CHECK(f != NULL);
    char io_buffer[65536];
    CHECK(setvbuf(f, io_buffer, _IOFBF, sizeof(io_buffer)) == 0);
    char block[4096];
    memset(block, 'x', sizeof(block));
    for (off_t pos = 0; pos < extent; pos += sizeof(block))
        CHECK(fwrite(block, 1, sizeof(block), f) == sizeof(block));
    CHECK(fflush(f) == 0);
    for (int run = 0; run < 3; run++) {
        struct phase_log log = {0};
        double start = now();
        poll(f, &log, baseline);
        printf("run=%d first_poll_bytes=%zu first_poll_seconds=%.6f\n",
               run + 1, bytes, now() - start);
        size_t total = bytes;
        unsigned int polls = 1;
        while (log.offset < extent) {
            off_t before = log.offset;
            poll(f, &log, baseline);
            CHECK(log.offset > before);
            total += bytes;
            CHECK(++polls <= 4);
        }
        CHECK(log.offset == extent && total == (size_t)extent);
        if (!baseline) CHECK(polls == 4);
        for (int i = 0; i < LOG_PHASE_COUNT; i++) CHECK(!log.seen[i]);
        poll(f, &log, baseline);
        CHECK(bytes == 0);
    }
    /* Every marker crosses the per-poll boundary. Use both short and long
     * retained prefixes, then verify all remaining bytes are consumed once. */
    for (int phase = 0; phase < LOG_PHASE_COUNT; phase++) {
        const char *marker = phase_markers[phase];
        size_t length = strlen(marker);
        for (size_t split = 1; split < length; split += length - 2) {
            CHECK(ftruncate(fileno(f), 0) == 0);
            CHECK(fseeko(f, budget - (off_t)split, SEEK_SET) == 0);
            CHECK(fputs(marker, f) >= 0 && fflush(f) == 0);
            struct phase_log log = {0};
            poll(f, &log, baseline);
            if (!baseline) {
                CHECK(log.offset == budget && !log.seen[phase]);
                poll(f, &log, baseline);
                CHECK(bytes == length - split);
            }
            CHECK(log.offset == budget + (off_t)(length - split));
            for (int i = 0; i < LOG_PHASE_COUNT; i++)
                CHECK(log.seen[i] == (i == phase));
        }
    }
    /* Truncation between budgeted turns discards a retained partial marker. */
    CHECK(ftruncate(fileno(f), 0) == 0);
    CHECK(fseeko(f, budget - 10, SEEK_SET) == 0);
    CHECK(fputs("FlyClient PASSED", f) >= 0 && fflush(f) == 0);
    struct phase_log log = {0};
    poll(f, &log, baseline);
    if (!baseline) {
        CHECK(!log.seen[LOG_FLYCLIENT]);
        CHECK(ftruncate(fileno(f), 0) == 0);
        CHECK(fseeko(f, 0, SEEK_SET) == 0);
        CHECK(fputs("PASSED", f) >= 0 && fflush(f) == 0);
        poll(f, &log, false);
        CHECK(log.offset == 6 && !log.seen[LOG_FLYCLIENT]);
    }
    CHECK(fclose(f) == 0);
    puts(baseline ? "PASS: baseline measurements and marker behavior (budget not enforced)" :
         "PASS: bounded turns, exact eventual scan, idle poll, boundary markers, truncation");
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$baseline"
