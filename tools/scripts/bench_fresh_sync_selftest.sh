#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic phase-log regression and observer-cost benchmark. No node is run.
# Usage: bash tools/scripts/bench_fresh_sync_selftest.sh [source.c]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${1:-$ROOT/tools/bench_fresh_sync.c}"
TMP="$(mktemp -d /tmp/zcl-phase-log.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# Compile the actual scanner with a counted fread; do not duplicate its logic.
cat > "$TMP/test.c" <<'EOF'
#include "platform/time_compat.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <sys/stat.h>
#include <unistd.h>

#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static size_t read_bytes, read_calls;
static bool fail_read;
static const char *append_during_read;
static size_t counted_read(void *buf, size_t size, size_t count, FILE *f)
{
    read_calls++;
    if (fail_read) return 0;
    if (append_during_read) {
        struct stat st;
        CHECK(fstat(fileno(f), &st) == 0);
        size_t n = strlen(append_during_read);
        CHECK(pwrite(fileno(f), append_during_read, n, st.st_size) == (ssize_t)n);
        append_during_read = NULL;
    }
    size_t n = fread(buf, size, count, f);
    read_bytes += n * size;
    return n;
}
#define fread counted_read
EOF
awk '/^enum log_phase / { copy = 1 }
     /^\/\* Check if HTTPS/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'EOF'
#undef fread
static void append(FILE *f, const void *buf, size_t n)
{
    CHECK(fseeko(f, 0, SEEK_END) == 0);
    CHECK(fwrite(buf, 1, n, f) == n);
    CHECK(fflush(f) == 0);
}
int main(void)
{
    char padding[4096];
    memset(padding, 'x', sizeof(padding));
    padding[sizeof(padding) - 1] = '\n';
    /* Every split position, both across a read boundary and across polls. */
    for (int phase = 0; phase < LOG_PHASE_COUNT; phase++) {
        const char *marker = phase_markers[phase];
        size_t len = strlen(marker);
        for (size_t split = 1; split < len; split++) {
            for (int between_polls = 0; between_polls <= 1; between_polls++) {
                FILE *f = tmpfile();
                CHECK(f != NULL);
                struct phase_log log = {0};
                append(f, padding, sizeof(padding) - split);
                append(f, marker, split);
                if (between_polls) {
                    CHECK(phase_log_poll(f, &log));
                    CHECK(!log.seen[phase]);
                }
                append(f, marker + split, len - split);
                CHECK(phase_log_poll(f, &log));
                for (int i = 0; i < LOG_PHASE_COUNT; i++)
                    CHECK(log.seen[i] == (i == phase));
                size_t before = read_bytes;
                CHECK(phase_log_poll(f, &log));
                CHECK(read_bytes == before);
                CHECK(fclose(f) == 0);
            }
        }
    }
    FILE *f = tmpfile();
    CHECK(f != NULL);
    struct phase_log log = {0};
    CHECK(phase_log_poll(f, &log)); /* Empty is not a phase observation. */
    for (int i = 0; i < LOG_PHASE_COUNT; i++) CHECK(!log.seen[i]);
    const char binary[] = "FlyClient\0 PASSED\nFile sync downloading";
    append(f, binary, sizeof(binary) - 1);
    CHECK(phase_log_poll(f, &log));
    CHECK(log.seen[LOG_FILE_START] && !log.seen[LOG_FLYCLIENT]);
    /* A truncation discards the old partial suffix, retaining seen phases. */
    append(f, "FlyClient ", 10);
    CHECK(phase_log_poll(f, &log));
    CHECK(ftruncate(fileno(f), 0) == 0);
    append(f, "PASSED", 6);
    CHECK(phase_log_poll(f, &log));
    CHECK(!log.seen[LOG_FLYCLIENT] && log.seen[LOG_FILE_START]);
    FILE *replacement = tmpfile();
    CHECK(replacement != NULL);
    append(replacement, "FlyClient PASSED", 16);
    CHECK(phase_log_poll(replacement, &log));
    CHECK(log.seen[LOG_FLYCLIENT] && log.seen[LOG_FILE_START]);
    CHECK(fclose(replacement) == 0);
    CHECK(fclose(f) == 0);

    f = tmpfile();
    CHECK(f != NULL);
    log = (struct phase_log){0};
    append(f, padding, sizeof(padding));
    fail_read = true;
    CHECK(!phase_log_poll(f, &log));
    CHECK(log.offset == 0);
    fail_read = false;
    append_during_read = "verifying -> complete";
    CHECK(phase_log_poll(f, &log));
    CHECK(log.offset == sizeof(padding) && !log.seen[LOG_SNAPSHOT_DONE]);
    CHECK(phase_log_poll(f, &log));
    CHECK(log.seen[LOG_SNAPSHOT_DONE]);
    for (int i = 0; i < LOG_PHASE_COUNT; i++) {
        append(f, phase_markers[i], strlen(phase_markers[i]));
        append(f, "\n", 1);
    }
    CHECK(phase_log_poll(f, &log));
    for (int i = 0; i < LOG_PHASE_COUNT; i++) CHECK(log.seen[i]);
    CHECK(fclose(f) == 0);

    /* Same absent-marker workload as the old five full scans per poll. */
    f = tmpfile();
    CHECK(f != NULL);
    for (int i = 0; i < 4096; i++) append(f, padding, sizeof(padding));
    log = (struct phase_log){0};
    read_bytes = read_calls = 0;
    int64_t begin = platform_time_monotonic_us();
    for (int i = 0; i < 20; i++) CHECK(phase_log_poll(f, &log));
    int64_t elapsed = platform_time_monotonic_us() - begin;
    CHECK(read_bytes == 16 * 1024 * 1024);
    CHECK(read_calls == 258); /* two 4 KiB reads, then 256 bulk reads */
    for (int i = 0; i < LOG_PHASE_COUNT; i++) CHECK(!log.seen[i]);
    CHECK(fclose(f) == 0);
    printf("PASS: splits, append, unchanged, binary, truncation, replacement, read failure, bounded growth\n");
    printf("20 polls, 16 MiB log: %zu bytes read, %zu reads, %.6f seconds\n",
           read_bytes, read_calls, (double)elapsed / 1000000.0);
    return 0;
}
EOF
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror -D_DEFAULT_SOURCE \
    -I"$ROOT/platform/modules/platform/include" \
    -I"$ROOT/platform/modules/base/include" -I"$ROOT/platform/modules/util/include" \
    "$TMP/test.c" "$ROOT/platform/modules/platform/src/clock.c" \
    "$ROOT/platform/modules/base/src/log_level.c" -o "$TMP/test"
"$TMP/test"
