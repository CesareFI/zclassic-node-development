#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exact small-append read budget through the real phase-log opener/scanner.
# Usage: bash tools/scripts/bench_fresh_sync_small_append_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-small-append.XXXXXX")
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
awk '/^enum log_phase / { copy = 1; starts++ }
     /^\/\* Check if HTTPS/ { copy = 0; ends++ }
     copy { print }
     END { if (starts != 1 || ends != 1) exit 1 }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
static struct phase_log observe(const char *logfile, struct phase_log phases)
{
C
awk '/            FILE \*phase_file = fopen/ { copy = 1; starts++ }
     copy && /^        }/ { ends++; exit }
     copy { print }
     END { if (starts != 1 || ends != 1) exit 1 }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
    return phases;
}
static bool read_io(unsigned long long *bytes, unsigned long long *calls)
{
    FILE *f = fopen("/proc/self/io", "r");
    if (!f) return false;
    char line[128];
    bool got_bytes = false, got_calls = false;
    while (fgets(line, sizeof(line), f)) {
        if (sscanf(line, "rchar: %llu", bytes) == 1) got_bytes = true;
        if (sscanf(line, "syscr: %llu", calls) == 1) got_calls = true;
    }
    CHECK(fclose(f) == 0);
    return got_bytes && got_calls;
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
    bool baseline = strcmp(argv[2], "1") == 0;
    char block[73729];
    memset(block, 'x', sizeof(block));
    const size_t sizes[] = {1, 100, 4095, 4096, 4097, 8191, 8192, 8193,
                            16384, 65536, 73727, 73728, 73729};
    for (size_t s = 0; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
        FILE *writer = fopen(argv[1], "w");
        CHECK(writer != NULL);
        /* Deliberately unaligned initial extent, including 4 KiB appends. */
        CHECK(fwrite(block, 1, sizeof(block), writer) == sizeof(block));
        CHECK(fflush(writer) == 0);
        struct phase_log phases = observe(argv[1], (struct phase_log){0});
        CHECK(phases.offset == (off_t)sizeof(block));
        unsigned long long before = 0, after = 0;
        unsigned long long calls_before = 0, calls_after = 0;
        bool measured = read_io(&before, &calls_before);
        double start = now();
        for (int poll = 0; poll < 1000; poll++) {
            CHECK(fwrite(block, 1, sizes[s], writer) == sizes[s]);
            CHECK(fflush(writer) == 0);
            phases = observe(argv[1], phases);
            CHECK(phases.offset == (off_t)(sizeof(block) + sizes[s] * (poll + 1)));
            for (int i = 0; i < LOG_PHASE_COUNT; i++) CHECK(!phases.seen[i]);
        }
        double elapsed = now() - start;
        measured = read_io(&after, &calls_after) && measured;
        printf("append=%zu polls=1000 appended_bytes=%zu seconds=%.6f",
               sizes[s], sizes[s] * 1000, elapsed);
        if (measured) {
            CHECK(after >= before && calls_after >= calls_before);
            printf(" read_bytes=%llu read_syscalls=%llu\n",
                   after - before, calls_after - calls_before);
            /* Allow only the small accounting read above the new payload.
             * Larger appends retain bulk buffering and its read-ahead. */
            if (!baseline && sizes[s] <= 73728) {
                CHECK(after - before <= sizes[s] * 1000 + 4096);
                /* Two early-stop reads, then one bulk scanner read,
                 * plus the two accounting reads. */
                size_t reads = sizes[s] <= 8192 ? (sizes[s] + 4095) / 4096 : 3;
                CHECK(calls_after - calls_before <=
                      reads * 1000 + 2);
            }
        } else puts(" read_budget=UNOBSERVED (/proc/self/io unavailable)");
        /* Every marker can cross small-append polls after either mode. */
        for (int i = 0; i < LOG_PHASE_COUNT; i++) {
            for (const char *p = phase_markers[i]; *p; p++) {
                CHECK(fputc(*p, writer) != EOF && fflush(writer) == 0);
                phases = observe(argv[1], phases);
                CHECK(phases.seen[i] == (p[1] == '\0'));
            }
            CHECK(fputc('\n', writer) != EOF && fflush(writer) == 0);
        }
        CHECK(fclose(writer) == 0);
    }
    puts(baseline ? "BASELINE: small-append read amplification measured" :
         "PASS: exact small-append read budget, buffer threshold, cursors, split milestones");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$fixture/node.log" "$baseline"
