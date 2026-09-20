#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Growing-log observation cost; no node or network. Optional baseline reports
# old read amplification without accepting it as the regression budget.
# Usage: bash tools/scripts/bench_fresh_sync_growth_io_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-growth-io.XXXXXX")
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
    bool baseline = strcmp(argv[2], "1") == 0;
    char block[4096];
    memset(block, 'x', sizeof(block));
    block[sizeof(block) - 1] = '\n';
    for (int trial = 0; trial < 3; trial++) {
        FILE *writer = fopen(argv[1], "w");
        CHECK(writer != NULL);
        for (int i = 0; i < 32; i++)
            CHECK(fwrite(block, 1, sizeof(block), writer) == sizeof(block));
        CHECK(fflush(writer) == 0);
        struct phase_log phases = observe(argv[1], (struct phase_log){0});
        CHECK(phases.offset == 32 * (off_t)sizeof(block));
        unsigned long long before = 0, after = 0;
        bool measured = read_bytes(&before);
        double start = now();
        for (int poll = 0; poll < 10000; poll++) {
            CHECK(fwrite(block, 1, 100, writer) == 100 && fflush(writer) == 0);
            phases = observe(argv[1], phases);
            CHECK(phases.offset == 32 * (off_t)sizeof(block) + 100 * (poll + 1));
            for (int i = 0; i < LOG_PHASE_COUNT; i++) CHECK(!phases.seen[i]);
        }
        double elapsed = now() - start;
        measured = read_bytes(&after) && measured;
        printf("trial=%d polls=10000 appended_bytes=1000000 seconds=%.6f", trial + 1, elapsed);
        if (measured) {
            printf(" read_bytes=%llu\n", after - before);
            if (!baseline) CHECK(after >= before && after - before < 45000000);
        } else puts(" read_budget=UNOBSERVED (/proc/self/io unavailable)");
        /* Partial markers still span polls and buffer boundaries. */
        CHECK(fputs("FlyClient ", writer) >= 0 && fflush(writer) == 0);
        phases = observe(argv[1], phases);
        CHECK(!phases.seen[LOG_FLYCLIENT]);
        CHECK(fputs("PASSED", writer) >= 0 && fflush(writer) == 0);
        phases = observe(argv[1], phases);
        CHECK(phases.seen[LOG_FLYCLIENT]);
        CHECK(fclose(writer) == 0);
    }
    puts(baseline ? "BASELINE: growing-log reads measured" :
         "PASS: growing-log read budget, exact cursors, split marker");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$fixture/node.log" "$baseline"
