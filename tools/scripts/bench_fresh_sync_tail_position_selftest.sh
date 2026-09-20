#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Isolated startup-tail positioning cost and output regression; no node needed.
# Usage: bash tools/scripts/bench_fresh_sync_tail_position_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-tail-position.XXXXXX")
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
static unsigned long positions;
static int count_seek(FILE *f, off_t offset, int whence)
{
    positions++;
    return fseeko(f, offset, whence);
}
static off_t count_tell(FILE *f)
{
    positions++;
    return ftello(f);
}
#define fseeko count_seek
#define ftello count_tell
C
awk '/^static void startup_log_tail\(/ { copy = 1; starts++ }
     /^\/\* Capture complete/ { copy = 0; ends++ }
     copy { print }
     END { if (starts != 1 || ends != 1) exit 1 }' \
    "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef fseeko
#undef ftello
static void write_log(const char *path, const char *body, size_t length)
{
    FILE *f = fopen(path, "wb");
    CHECK(f != NULL);
    CHECK(fwrite(body, 1, length, f) == length);
    CHECK(fclose(f) == 0);
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
    /* Retain a reference when the candidate no longer calls ftello. */
    (void)count_tell;
    char line[256], body[8193];
    const char *inputs[] = {"", "progress", "progress\n", "old\nnew\n", "old\n\n"};
    const char *outputs[] = {"", "progress", "progress\n", "new\n", "\n"};
    for (size_t i = 0; i < sizeof(inputs) / sizeof(inputs[0]); i++) {
        write_log(argv[1], inputs[i], strlen(inputs[i]));
        startup_log_tail(argv[1], line, sizeof(line));
        CHECK(strcmp(line, outputs[i]) == 0);
    }
    memset(body, 'x', sizeof(body));
    write_log(argv[1], body, sizeof(line));
    startup_log_tail(argv[1], line, sizeof(line));
    CHECK(line[0] == '\0');
    write_log(argv[1], body, sizeof(line) - 1);
    startup_log_tail(argv[1], line, sizeof(line));
    CHECK(strlen(line) == sizeof(line) - 1);
    memcpy(body + sizeof(body) - 10, "\nprogress\n", 10);
    write_log(argv[1], body, sizeof(body));
    bool budget_ok = true;
    for (int trial = 0; trial < 3; trial++) {
        positions = 0;
        double start = now();
        for (int repeat = 0; repeat < 10000; repeat++) {
            startup_log_tail(argv[1], line, sizeof(line));
            CHECK(strcmp(line, "progress\n") == 0);
        }
        printf("trial=%d observations=10000 positioning_calls=%lu wall_ms=%.3f\n",
               trial + 1, positions, (now() - start) * 1000.0);
        if (positions > 10000) budget_ok = false;
    }
    CHECK(unlink(argv[1]) == 0);
    bool baseline = strcmp(argv[2], "1") == 0;
    if (!baseline) CHECK(budget_ok);
    puts(baseline ? "BASELINE: exact startup tails and positioning cost measured" :
         "PASS: exact startup tails and positioning budget");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 30 "$fixture/test" "$fixture/node.log" "$baseline"
