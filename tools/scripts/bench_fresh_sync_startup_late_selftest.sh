#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure startup deadline admission under scheduling and filesystem delays.
# Usage: bash tools/scripts/bench_fresh_sync_startup_late_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-startup-late.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
#define R_OK 4
#define WNOHANG 1
static int g_child = 42, scenario, opens, diagnostics, late_accesses;
static int64_t elapsed_us, ready_us;
static double now_sec(void) { return (double)elapsed_us / 1000000.0; }
static int access(const char *path, int flags)
{
    CHECK(strcmp(path, "fixture.cookie") == 0 && flags == R_OK);
    if (scenario == 4 && elapsed_us >= 299500000) elapsed_us += 500001;
    /* No cookie at the deadline: a second lookup would find a late one. */
    if (scenario == 6 && elapsed_us >= 300000000) {
        if (late_accesses++ == 0) return -1;
        elapsed_us++;
    }
    return elapsed_us >= ready_us ? 0 : -1;
}
static int usleep(unsigned int usec)
{
    CHECK(usec > 0 && usec <= 500000);
    elapsed_us += usec;
    if (scenario == 3 && elapsed_us == 300000000) elapsed_us++;
    CHECK(elapsed_us <= 301000000);
    return 0;
}
static pid_t waitpid(pid_t child, int *status, int flags)
{
    CHECK(child == g_child && flags == WNOHANG);
    *status = 0;
    return 0;
}
static void startup_log_tail(const char *path, char *out, size_t size)
{
    CHECK(strcmp(path, "fixture.log") == 0 && size > 0);
    out[0] = '\0';
}
static int fixture_system(const char *cmd)
{
    CHECK(strcmp(cmd, "tail -10 'fixture.log'") == 0);
    diagnostics++;
    return 0;
}
static FILE *fixture_fopen(const char *path, const char *mode)
{
    CHECK(strcmp(path, "fixture.cookie") == 0 && strcmp(mode, "r") == 0);
    FILE *f = tmpfile();
    CHECK(f != NULL && fputs(
        "__cookie__:0123456789abcdef0123456789abcdef\n", f) >= 0);
    rewind(f);
    opens++;
    return f;
}
static int fixture_fclose(FILE *f)
{
    if (scenario == 5) elapsed_us += 500001;
    return fclose(f);
}
#define system fixture_system
#define fopen fixture_fopen
#define fclose fixture_fclose
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
    int accepted_late = 0;
    for (scenario = 0; scenario < 7; scenario++) {
        elapsed_us = 0;
        opens = diagnostics = late_accesses = 0;
        ready_us = scenario == 0 ? 0 :
                   scenario == 1 || scenario == 5 ? 299500000 : 300000000;
        char cookie[256] = "";
        bool ready = wait_for_cookie("fixture.cookie", "fixture.log", 0,
                                     cookie, sizeof(cookie));
        printf("scenario=%d ready=%d elapsed_seconds=%.6f cookie_opens=%d\n",
               scenario, ready, now_sec(), opens);
        CHECK(ready == (baseline || scenario < 3));
        CHECK(strcmp(cookie, ready ?
                     "__cookie__:0123456789abcdef0123456789abcdef" : "") == 0);
        CHECK(g_child == 42);
        if (scenario >= 3 && ready) accepted_late++;
        if (!baseline && (scenario == 3 || scenario == 4 || scenario == 6))
            CHECK(opens == 0 && diagnostics == 1);
        if (!baseline && scenario == 5) CHECK(opens == 1);
    }
    printf("late startup admissions=%d/4\n", accepted_late);
    puts(baseline ? "BASELINE: late cookie admission reproduced" :
         "PASS: on-time cookies accepted, late observations and reads refused");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 5 "$fixture/test" "$baseline"
