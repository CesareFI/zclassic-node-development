#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# No-growth phase-log polling cost and cursor behavior; isolated files, no node.
# Usage: bash tools/scripts/bench_fresh_sync_idle_log_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d /tmp/zcl-idle-phase.XXXXXX)
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
static size_t seeks;
static int counted_seek(FILE *f, off_t offset, int whence)
{
    seeks++;
    return fseeko(f, offset, whence);
}
#define fseeko counted_seek
C
awk '/^enum log_phase / { copy = 1 }
     /^\/\* Check if HTTPS/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef fseeko
static struct phase_log observe(const char *logfile, struct phase_log phases)
{
C
awk '/            FILE \*phase_file = fopen/ { copy = 1 }
     copy && /^        }/ { exit }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
    return phases;
}
static void write_text(const char *path, const char *mode, const char *text)
{
    FILE *f = fopen(path, mode);
    CHECK(f != NULL);
    CHECK(fputs(text, f) >= 0);
    CHECK(fclose(f) == 0);
}
static double now(void)
{
    struct timespec ts;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
/* Optional Linux accounting includes this observer's one proc read. */
static long long read_calls(void)
{
    FILE *f = fopen("/proc/self/io", "r");
    if (!f) return -1;
    char line[128];
    long long value = -1;
    while (fgets(line, sizeof(line), f))
        if (sscanf(line, "syscr: %lld", &value) == 1) break;
    CHECK(fclose(f) == 0);
    return value;
}
int main(int argc, char **argv)
{
    CHECK(argc == 4);
    const char *path = argv[1], *replacement = argv[2];
    bool baseline = strcmp(argv[3], "1") == 0;
    /* Deliberately unaligned EOF: stdio seeking can read a partial buffer. */
    write_text(path, "w", "File sync downloading\nFlyClient ");
    struct phase_log phases = observe(path, (struct phase_log){0});
    CHECK(phases.seen[LOG_FILE_START] && !phases.seen[LOG_FLYCLIENT]);
    for (int run = 0; run < 3; run++) {
        seeks = 0;
        long long before = read_calls();
        double start = now();
        for (int repeat = 0; repeat < 10000; repeat++) {
            struct phase_log next = observe(path, phases);
            CHECK(next.offset == phases.offset && next.tail_len == phases.tail_len);
            CHECK(memcmp(next.tail, phases.tail, phases.tail_len) == 0);
            for (int i = 0; i < LOG_PHASE_COUNT; i++)
                CHECK(next.seen[i] == phases.seen[i]);
            phases = next;
        }
        double elapsed = now() - start;
        long long after = read_calls();
        printf("run=%d polls=10000 seeks=%zu read_syscalls=%lld seconds=%.6f\n",
               run + 1, seeks, before < 0 || after < 0 ? -1 : after - before, elapsed);
        if (!baseline) CHECK(seeks == 0);
    }
    /* The no-growth path must preserve a partial marker for a later append. */
    write_text(path, "a", "PASSED");
    phases = observe(path, phases);
    CHECK(phases.seen[LOG_FLYCLIENT]);
    write_text(path, "a", "\nnegotiating -> ");
    phases = observe(path, phases);
    CHECK(!phases.seen[LOG_SNAPSHOT_START]);
    /* Truncate to empty, poll idle, then append: never join the old suffix. */
    write_text(path, "w", "");
    phases = observe(path, phases);
    CHECK(phases.offset == 0 && phases.tail_len == 0);
    phases = observe(path, phases);
    write_text(path, "a", "receiving");
    phases = observe(path, phases);
    CHECK(!phases.seen[LOG_SNAPSHOT_START] && phases.seen[LOG_FLYCLIENT]);
    /* Equal-length replacement must reset identity before the idle test. */
    write_text(path, "w", "xxxxxxxxxxxxxxxxxx");
    phases = observe(path, phases);
    CHECK(phases.offset == 18 && !phases.seen[LOG_FILE_DONE]);
    write_text(replacement, "w", "File sync complete");
    CHECK(rename(replacement, path) == 0);
    phases = observe(path, phases);
    CHECK(phases.offset == 18 && phases.seen[LOG_FILE_DONE]);
    CHECK(phases.seen[LOG_FILE_START] && phases.seen[LOG_FLYCLIENT]);
    puts("PASS: idle work, split append, empty truncation, equal-size replacement, retained phases");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$fixture/node.log" "$fixture/replacement.log" "$baseline"
