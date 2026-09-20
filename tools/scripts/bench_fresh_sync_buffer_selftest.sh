#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure the actual phase-log opener and scanner on isolated warm-cache logs.
# Usage: bash tools/scripts/bench_fresh_sync_buffer_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d /tmp/zcl-phase-buffer.XXXXXX)
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
static bool buffer_failure;
/* External linkage also supports baselines that never configure a buffer. */
int configure_buffer(FILE *f, char *buf, int mode, size_t size)
{
    if (buffer_failure) return -1;
    return setvbuf(f, buf, mode, size);
}
#define setvbuf configure_buffer
C
awk '/^enum log_phase / { copy = 1 }
     /^\/\* Check if HTTPS/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
static struct phase_log observe(const char *logfile, struct phase_log phases)
{
C
awk '/            FILE \*phase_file = fopen/ { copy = 1 }
     copy && /^        }/ { exit }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
    return phases;
}
/* Optional Linux measurement; other hosts still run the behavior fixtures. */
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
    CHECK(argc == 3);
    const bool baseline = strcmp(argv[2], "1") == 0;
    const size_t extent = 64 * 1024 * 1024;
    FILE *f = fopen(argv[1], "w");
    CHECK(f != NULL);
    char block[4096];
    memset(block, 'x', sizeof(block));
    for (size_t pos = 0; pos < extent; pos += sizeof(block))
        CHECK(fwrite(block, 1, sizeof(block), f) == sizeof(block));
    CHECK(fseeko(f, (off_t)extent - 32, SEEK_SET) == 0);
    CHECK(fputs(phase_markers[LOG_FLYCLIENT], f) >= 0);
    CHECK(fclose(f) == 0);
    for (int run = 0; run < 3; run++) {
        long long before = read_calls();
        double start = now();
        for (int repeat = 0; repeat < 20; repeat++) {
            struct phase_log phases = observe(argv[1], (struct phase_log){0});
            while (phases.offset < (off_t)extent) {
                off_t before_offset = phases.offset;
                phases = observe(argv[1], phases);
                CHECK(phases.offset > before_offset);
            }
            CHECK(phases.offset == (off_t)extent);
            for (int i = 0; i < LOG_PHASE_COUNT; i++)
                CHECK(phases.seen[i] == (i == LOG_FLYCLIENT));
            struct phase_log again = observe(argv[1], phases);
            CHECK(again.offset == phases.offset);
        }
        double elapsed = now() - start;
        long long after = read_calls();
        printf("run=%d scans=20 log_mib=64 seconds=%.6f read_syscalls=%lld\n",
               run + 1, elapsed, before < 0 || after < 0 ? -1 : after - before);
        if (!baseline && before >= 0 && after >= 0)
            CHECK(after - before < 22000);
    }
    /* Failure to configure the optional buffer retains ordinary stdio. */
    buffer_failure = true;
    struct phase_log phases = observe(argv[1], (struct phase_log){0});
    while (phases.offset < (off_t)extent) {
        off_t before_offset = phases.offset;
        phases = observe(argv[1], phases);
        CHECK(phases.offset > before_offset);
    }
    CHECK(phases.offset == (off_t)extent && phases.seen[LOG_FLYCLIENT]);
    buffer_failure = false;
    /* Exercise both scanner and stdio boundaries through the actual opener. */
    const size_t boundaries[] = {4096, 65536};
    for (size_t b = 0; b < sizeof(boundaries) / sizeof(boundaries[0]); b++) {
        for (int phase = 0; phase < LOG_PHASE_COUNT; phase++) {
            const char *marker = phase_markers[phase];
            for (size_t split = 1; split < strlen(marker); split++) {
                f = fopen(argv[1], "w");
                CHECK(f != NULL);
                CHECK(fseeko(f, (off_t)(boundaries[b] - split), SEEK_SET) == 0);
                CHECK(fputs(marker, f) >= 0 && fclose(f) == 0);
                phases = observe(argv[1], (struct phase_log){0});
                for (int i = 0; i < LOG_PHASE_COUNT; i++)
                    CHECK(phases.seen[i] == (i == phase));
            }
        }
    }
    f = fopen(argv[1], "w");
    CHECK(f != NULL);
    for (int i = 0; i < LOG_PHASE_COUNT; i++)
        CHECK(fprintf(f, "%s\n", phase_markers[i]) > 0);
    CHECK(fclose(f) == 0);
    phases = observe(argv[1], (struct phase_log){0});
    for (int i = 0; i < LOG_PHASE_COUNT; i++) CHECK(phases.seen[i]);
    CHECK(unlink(argv[1]) == 0);
    phases = observe(argv[1], (struct phase_log){0});
    CHECK(phases.offset == 0);
    for (int i = 0; i < LOG_PHASE_COUNT; i++) CHECK(!phases.seen[i]);
    puts("PASS: late/absent/early milestones, all boundary splits, unchanged extent, buffer refusal, missing log");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$fixture/node.log" "$baseline"
