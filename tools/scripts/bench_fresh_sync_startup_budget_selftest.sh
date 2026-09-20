#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Startup budget uses elapsed time despite interrupted sleeps or observer work.
# Usage: bash tools/scripts/bench_fresh_sync_startup_budget_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
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
source_file=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/zcl-startup-budget.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
#define R_OK 4
#define WNOHANG 1
static int g_child = 42, scenario, sleeps, progress, diagnostics;
static long elapsed_us, previous_progress_us;
static double now_sec(void) { return 100.0 + (double)elapsed_us / 1000000.0; }
static int access(const char *path, int flags)
{
    CHECK(strcmp(path, "fixture.cookie") == 0 && flags == R_OK);
    return (scenario == 1 && elapsed_us >= 120000000) ||
           (scenario == 4 && elapsed_us >= 300000000) ? 0 : -1;
}
static int usleep(unsigned int usec)
{
    CHECK(usec > 0 && usec <= 500000 && ++sleeps < 10000);
    if (scenario == 1 || scenario == 2) {
        elapsed_us += usec < 125000 ? usec : 125000;
        errno = EINTR;
        return -1;
    }
    elapsed_us += usec;
    return 0;
}
static pid_t waitpid(pid_t child, int *status, int flags)
{
    CHECK(child == 42 && flags == WNOHANG);
    *status = 0;
    return 0;
}
static long shortest_progress_us;
static void startup_log_tail(const char *path, char *out, size_t size)
{
    CHECK(strcmp(path, "fixture.log") == 0);
    long interval = elapsed_us - previous_progress_us;
    if (interval < shortest_progress_us) shortest_progress_us = interval;
    previous_progress_us = elapsed_us;
    progress++;
    if (scenario == 3) elapsed_us += 250000; /* real observer work costs time */
    CHECK(snprintf(out, size, "startup progress") < (int)size);
}
static int fixture_system(const char *cmd)
{
    CHECK(strcmp(cmd, "tail -10 'fixture.log'") == 0);
    diagnostics++;
    return 0;
}
#define system fixture_system
static FILE *fixture_fopen(const char *path, const char *flags)
{
    CHECK(strcmp(path, "fixture.cookie") == 0 && strcmp(flags, "r") == 0);
    FILE *f = tmpfile();
    CHECK(f != NULL);
    CHECK(fputs("fixture:fixture\n", f) >= 0);
    rewind(f);
    return f;
}
#define fopen fixture_fopen
C
awk '/^static void startup_progress\(/ { copy = 1 }
     /^static bool benchmark_paths\(|^int main\(/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    for (scenario = 0; scenario < 5; scenario++) {
        elapsed_us = previous_progress_us = 0;
        shortest_progress_us = 1000000000;
        sleeps = progress = diagnostics = 0;
        char cookie[256] = "";
        bool ready = wait_for_cookie("fixture.cookie", "fixture.log", 100,
                                     cookie, sizeof(cookie));
        printf("scenario=%d ready=%d seconds=%.3f sleeps=%d progress=%d shortest_progress=%.3f\n",
               scenario, ready, now_sec() - 100, sleeps, progress,
               (double)shortest_progress_us / 1000000.0);
        if (baseline) continue;
        CHECK(ready == (scenario == 1 || scenario == 4));
        CHECK(elapsed_us == (scenario == 1 ? 120000000 : 300000000));
        CHECK(shortest_progress_us >= 10000000);
        CHECK(diagnostics == (ready ? 0 : 1));
        CHECK(g_child == 42);
        CHECK(strcmp(cookie, ready ? "fixture:fixture" : "") == 0);
    }
    puts(baseline ? "BASELINE observations only" :
         "PASS: interrupted sleeps, observer cost, deadline cookie and ten-second progress cadence");
    return 0;
}
C
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror -pedantic \
    "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" -std=c23 -Wall -Wextra -Werror -fanalyzer \
        -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 5 "$fixture/test" "$baseline"
