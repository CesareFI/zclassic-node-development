#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Bound startup observer work under interrupted sleeps without a node or signals.
# Usage: bash tools/scripts/bench_fresh_sync_startup_sleep_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-startup-sleep.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
#define R_OK 4
#define WNOHANG 1
static int g_child = 42, scenario, sleeps, polls, accesses, progress, diagnostics;
static long elapsed_us;
static double now_sec(void) { return (double)elapsed_us / 1000000.0; }
static int access(const char *path, int flags)
{
    CHECK(strcmp(path, "fixture.cookie") == 0 && flags == R_OK);
    accesses++;
    return scenario < 2 && elapsed_us >= 10000000 ? 0 : -1;
}
static int usleep(unsigned int usec)
{
    CHECK(usec > 0 && usec <= 500000 && ++sleeps < 100000);
    if (scenario == 3) { errno = EINVAL; return -1; }
    if (scenario != 0) {
        elapsed_us += usec < 5000 ? usec : 5000;
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
    polls++;
    return 0;
}
static void startup_log_tail(const char *path, char *out, size_t size)
{
    CHECK(strcmp(path, "fixture.log") == 0 && size > 0);
    progress++;
    out[0] = '\0';
}
static int fixture_system(const char *cmd)
{
    CHECK(strcmp(cmd, "tail -10 'fixture.log'") == 0);
    diagnostics++;
    return 0;
}
#define system fixture_system
static FILE *fixture_fopen(const char *path, const char *mode)
{
    CHECK(strcmp(path, "fixture.cookie") == 0 && strcmp(mode, "r") == 0);
    FILE *f = tmpfile();
    CHECK(f != NULL && fputs(
        "__cookie__:0123456789abcdef0123456789abcdef\n", f) >= 0);
    rewind(f);
    return f;
}
#define fopen fixture_fopen
C
awk '/^static void startup_progress\(/ { copy = 1; starts++ }
     /^static bool benchmark_paths\(|^int main\(/ { if (copy) ends++; copy = 0 }
     copy { print }
     END { if (starts != 1 || ends != 1) exit 1 }' \
    "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    for (scenario = 0; scenario < (baseline ? 3 : 4); scenario++) {
        elapsed_us = 0;
        sleeps = polls = accesses = progress = diagnostics = 0;
        char cookie[256] = "";
        bool ready = wait_for_cookie("fixture.cookie", "fixture.log", 0,
                                     cookie, sizeof(cookie));
        printf("scenario=%d ready=%d seconds=%.6f sleeps=%d polls=%d accesses=%d\n",
               scenario, ready, now_sec(), sleeps, polls, accesses);
        CHECK(ready == (scenario < 2));
        CHECK(elapsed_us == (scenario < 2 ? 10000000 :
                            scenario == 2 ? 300000000 : 0));
        CHECK(strcmp(cookie, ready ?
                     "__cookie__:0123456789abcdef0123456789abcdef" : "") == 0);
        CHECK(g_child == 42 && diagnostics == (scenario == 2 ? 1 : 0));
        CHECK(progress == (scenario == 2 ? 29 : 0));
        if (baseline) continue;
        CHECK(polls == (scenario < 2 ? 20 : scenario == 2 ? 600 : 0));
        CHECK(accesses <= polls + 2);
        if (scenario == 3) CHECK(sleeps == 1);
    }
    puts(baseline ? "BASELINE: startup observer work measured" :
         "PASS: bounded polling under signals, exact deadline, sleep-error refusal");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 5 "$fixture/test" "$baseline"
