#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Startup observations survive interrupted waits; no node or real sleep.
# Usage: bash tools/scripts/bench_fresh_sync_startup_interrupt_selftest.sh [--analyze] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
analyze=0
if [[ ${1:-} == --analyze ]]; then analyze=1; shift; fi
source_file=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/zcl-startup-interrupt.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <sys/types.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
#define R_OK 4
#define WNOHANG 1
static int g_child, sleeps, waits, interruptions, remaining, mode, diagnostics;
static double now_sec(void) { return sleeps * 0.5; }
static int access(const char *path, int flags)
{
    CHECK(strcmp(path, "fixture.cookie") == 0 && flags == R_OK);
    return sleeps == 21 ? 0 : -1;
}
static int usleep(unsigned int usec)
{
    CHECK(usec == 500000 && ++sleeps <= 21);
    return 0;
}
static pid_t waitpid(pid_t child, int *status, int flags)
{
    CHECK(child == 42 && flags == WNOHANG);
    CHECK(++waits <= 24);
    if (sleeps == 20) {
        if (remaining > 0) {
            remaining--;
            interruptions++;
            errno = EINTR;
            return -1; /* status deliberately untouched on interruption */
        }
        if (mode == 1) { *status = 1 << 8; return child; }
        if (mode == 2) { errno = ECHILD; return -1; }
    }
    return 0;
}
static void startup_log_tail(const char *path, char *out, size_t size)
{
    CHECK(strcmp(path, "fixture.log") == 0);
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
awk '/^static bool wait_for_cookie\(/ { copy = 1 }
     /^int main\(/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
int main(void)
{
    for (mode = 0; mode < 3; mode++) {
        for (int signals = 0; signals <= 3; signals++) {
            sleeps = waits = interruptions = diagnostics = 0;
            remaining = signals;
            g_child = 42;
            char cookie[256] = "";
            bool ready = wait_for_cookie("fixture.cookie", "fixture.log", 0,
                                         cookie, sizeof(cookie));
            printf("mode=%d signals=%d ready=%d simulated_seconds=%.1f waits=%d\n",
                   mode, signals, ready, now_sec(), waits);
            CHECK(ready == (mode == 0));
            CHECK(sleeps == (mode == 0 ? 21 : 20));
            CHECK(waits == sleeps + signals && interruptions == signals);
            CHECK(g_child == (mode == 0 ? 42 : 0));
            CHECK(diagnostics == (mode == 0 ? 0 : 1));
            CHECK(strcmp(cookie, mode == 0 ? "fixture:fixture" : "") == 0);
        }
    }
    puts("PASS: 12 startup cases; interruptions add no polling delay, death/errors still refuse");
    return 0;
}
C
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror -pedantic \
    "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" -std=c23 -Wall -Wextra -Werror -fanalyzer \
        -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 5 "$fixture/test"
