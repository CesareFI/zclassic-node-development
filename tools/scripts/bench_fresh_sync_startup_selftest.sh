#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the actual startup observer with a fake clock/child and inert cookie.
# Usage: bash tools/scripts/bench_fresh_sync_startup_selftest.sh [--analyze] [source.c]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
analyze=false
if [[ "${1:-}" == --analyze ]]; then analyze=true; shift; fi
SOURCE="${1:-$ROOT/tools/bench_fresh_sync.c}"
TMP="$(mktemp -d /tmp/zcl-bench-startup.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
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
static int g_child, mode, sleeps, waits, progress, diagnostics, opens;
static double now_sec(void) { return 100.0 + sleeps * 0.5; }
static int access(const char *path, int flags)
{
    CHECK(strcmp(path, "fixture.cookie") == 0 && flags == R_OK);
    if (mode == 2 || mode == 3 || mode == 5) return -1;
    int ready_at = mode == 1 ? 21 : mode == 4 ? 600 : 0;
    return sleeps >= ready_at ? 0 : -1;
}
static int usleep(unsigned int usec)
{
    CHECK(usec == 500000);
    sleeps++;
    CHECK(sleeps <= 600);
    return 0;
}
static int waitpid(int pid, int *status, int flags)
{
    CHECK(pid == 42 && flags == WNOHANG);
    waits++;
    *status = 0;
    if (mode == 5) return -1;
    return mode == 3 && sleeps == 3 ? pid : 0;
}
static int fixture_system(const char *cmd)
{
    CHECK(strcmp(cmd, "tail -10 'fixture.log'") == 0);
    diagnostics++;
    return 0;
}
#define system fixture_system
/* Either production reader must preserve the startup poll schedule. Their
 * actual I/O is covered by the progress and command-reader regressions. */
void startup_log_tail(const char *path, char *buf, size_t size)
{
    CHECK(strcmp(path, "fixture.log") == 0);
    CHECK(sleeps > 0 && sleeps % 20 == 0);
    progress++;
    CHECK(snprintf(buf, size, "fixture progress\n") < (int)size);
}
int run_cmd(const char *cmd, char *buf, int size)
{
    CHECK(strcmp(cmd, "tail -1 'fixture.log' 2>/dev/null") == 0);
    startup_log_tail("fixture.log", buf, (size_t)size);
    return (int)strlen(buf);
}
static FILE *fixture_fopen(const char *path, const char *flags)
{
    CHECK(strcmp(path, "fixture.cookie") == 0 && strcmp(flags, "r") == 0);
    opens++;
    if (mode == 7) { errno = EACCES; return NULL; }
    FILE *f = tmpfile();
    CHECK(f != NULL);
    if (mode == 10 || mode == 11) {
        for (int i = 0; i < (mode == 10 ? 256 : 255); i++)
            CHECK(fputc('x', f) != EOF);
    } else {
        CHECK(fputs(mode == 8 ? "" : mode == 9 ? "\n" :
                    mode == 6 ? "fixture:fixture" : "fixture:fixture\n", f) >= 0);
    }
    rewind(f);
    return f;
}
#define fopen fixture_fopen
static size_t fixture_fread(void *out, size_t size, size_t count, FILE *f)
{
    if (mode == 12) { errno = EIO; return 0; }
    return fread(out, size, count, f);
}
int fixture_ferror(FILE *f) { return mode == 12 ? 1 : ferror(f); }
int fixture_fgetc(FILE *f) { return mode == 12 ? EOF : fgetc(f); }
#define fread fixture_fread
#define ferror fixture_ferror
#define fgetc fixture_fgetc
C
if grep -q '^static bool wait_for_cookie(' "$SOURCE"; then
    awk '/^static void startup_progress\(/ { copy = 1 }
         /^static bool benchmark_paths\(|^int main\(/ { copy = 0 }
         copy { print }' "$SOURCE" >> "$TMP/test.c"
else
    # Adapt the old inline block to the same caller contract for comparison.
    cat >> "$TMP/test.c" <<'C'
static bool wait_for_cookie(const char *cookie_path, const char *logfile, double t0,
                            char *out, size_t out_size)
{
C
    awk '/^    printf\("Waiting for node startup/ { copy = 1 }
         /^    \/\* Phase timestamps/ { copy = 0 }
         copy { sub(/return 1;/, "return false;"); print }' "$SOURCE" >> "$TMP/test.c"
    cat >> "$TMP/test.c" <<'C'
    CHECK(snprintf(out, out_size, "%s", cookie) < (int)out_size);
    return true;
}
C
fi
cat >> "$TMP/test.c" <<'C'
int main(void)
{
    for (mode = 0; mode < 13; mode++) {
        g_child = 42;
        sleeps = waits = progress = diagnostics = opens = 0;
        char cookie[256] = "";
        bool ok = wait_for_cookie("fixture.cookie", "fixture.log", 100,
                                  cookie, sizeof(cookie));
        bool reached_cookie = mode != 2 && mode != 3 && mode != 5;
        bool expected = reached_cookie && mode != 7 && mode != 8 &&
                        mode != 9 && mode != 10 && mode != 12;
        int expected_sleeps = mode == 1 ? 21 : mode == 2 || mode == 4 ? 600 :
                              mode == 3 ? 3 : mode == 5 ? 1 : 0;
        CHECK(ok == expected);
        CHECK(sleeps == expected_sleeps && waits == sleeps);
        CHECK(progress == (sleeps > 0 ? (sleeps - 1) / 20 : 0));
        CHECK(diagnostics == (reached_cookie ? 0 : 1));
        CHECK(opens == (reached_cookie ? 1 : 0));
        CHECK(g_child == (mode == 3 || mode == 5 ? 0 : 42));
        if (mode == 11) {
            CHECK(strlen(cookie) == 255);
            for (int i = 0; i < 255; i++) CHECK(cookie[i] == 'x');
        } else {
            CHECK(strcmp(cookie, expected ? "fixture:fixture" : "") == 0);
        }
        printf("PASS: startup mode=%d ready=%d sleeps=%d progress=%d child=%d\n",
               mode, ok, sleeps, progress, g_child);
    }
    return 0;
}
C
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror "$TMP/test.c" -o "$TMP/test"
if "$analyze"; then
    "${CC:-cc}" -std=c23 -Wall -Wextra -Werror -fanalyzer \
        -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
timeout 5 "$TMP/test"
interrupt_args=()
if "$analyze"; then interrupt_args+=(--analyze); fi
bash "$ROOT/tools/scripts/bench_fresh_sync_startup_interrupt_selftest.sh" \
    "${interrupt_args[@]}" "$SOURCE"
