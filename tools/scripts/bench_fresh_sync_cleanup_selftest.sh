#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise benchmark teardown, with no node, network or persistent datadir.
# Usage: bash tools/scripts/bench_fresh_sync_cleanup_selftest.sh [--baseline] [source.c]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
SOURCE=${1:-$ROOT/tools/bench_fresh_sync.c}
TMP=$(mktemp -d /tmp/zcl-bench-cleanup.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static pid_t g_child;
#ifdef REAL_CHILD
static double now_sec(void)
{
    struct timespec ts;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}
#else
static double elapsed;
static int mode, terms, kills, waits, sleeps;
static bool reaped;
static double now_sec(void) { return elapsed; }
static int fixture_kill(pid_t pid, int sig)
{
    CHECK(pid == 42 && !reaped);
    if (sig == SIGTERM) terms++;
    else { CHECK(sig == SIGKILL); kills++; }
    return 0;
}
static pid_t fixture_wait(pid_t pid, int *status, int flags)
{
    CHECK(pid == 42);
    waits++;
    *status = 0;
    if (reaped || mode == 3) { errno = ECHILD; return -1; }
    if ((mode == 4 || mode == 5) && waits == 1) { errno = EINTR; return -1; }
    if (mode == 0 || (mode != 2 && mode != 5 && elapsed >= 0.025) || kills) {
        reaped = true;
        return pid;
    }
    CHECK(flags == WNOHANG);
    return 0;
}
static int fixture_usleep(unsigned int us)
{
    elapsed += (double)us / 1e6;
    sleeps++;
    return 0;
}
static int fixture_nanosleep(const struct timespec *request, struct timespec *remaining)
{
    (void)remaining;
    CHECK(request->tv_sec == 0 && request->tv_nsec > 0 && request->tv_nsec <= 10000000);
    elapsed += (double)request->tv_nsec / (mode == 4 || mode == 5 ? 2e9 : 1e9);
    sleeps++;
    CHECK(sleeps < 200);
    if (mode == 4 || mode == 5) { errno = EINTR; return -1; }
    return 0;
}
#define kill fixture_kill
#define waitpid fixture_wait
#define usleep fixture_usleep
#define nanosleep fixture_nanosleep
#endif
C
awk '/^static void cleanup\(/ { copy = 1 }
     /^static double now_sec\(/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
int main(int argc, char **argv)
{
    (void)argv;
#ifdef REAL_CHILD
    (void)argc;
    for (int run = 0; run < 3; run++) {
        int ready[2];
        CHECK(pipe(ready) == 0);
        g_child = fork();
        CHECK(g_child >= 0);
        if (g_child == 0) {
            close(ready[0]);
            sigset_t set;
            sigemptyset(&set);
            sigaddset(&set, SIGTERM);
            if (sigprocmask(SIG_BLOCK, &set, NULL) != 0) _exit(2);
            if (write(ready[1], "r", 1) != 1) _exit(3);
            int sig;
            if (sigwait(&set, &sig) != 0) _exit(4);
            struct timespec delay = {0, 20000000};
            while (nanosleep(&delay, &delay) != 0 && errno == EINTR) {}
            _exit(0);
        }
        close(ready[1]);
        char byte;
        CHECK(read(ready[0], &byte, 1) == 1);
        close(ready[0]);
        pid_t child = g_child;
        double start = now_sec();
        cleanup();
        printf("run=%d child_shutdown=20ms cleanup_seconds=%.6f\n", run, now_sec() - start);
        int status;
        CHECK(waitpid(child, &status, WNOHANG) == -1 && errno == ECHILD);
    }
#else
    bool baseline = argc > 1;
    /* Reference both sleep APIs so either source version compiles strictly. */
    (void)fixture_usleep; (void)fixture_nanosleep; (void)now_sec;
    for (mode = 0; mode < 6; mode++) {
        g_child = 42;
        elapsed = 0;
        terms = kills = waits = sleeps = 0;
        reaped = false;
        cleanup();
        CHECK(terms == 1);
        CHECK(kills == (mode == 2 || mode == 5 ? 1 : 0));
        CHECK(reaped || mode == 3);
        printf("mode=%d elapsed=%.6f sleeps=%d forced=%d\n", mode, elapsed, sleeps, kills);
        if (!baseline) {
            CHECK(g_child == 0);
            if (mode == 0 || mode == 3) CHECK(elapsed == 0 && sleeps == 0);
            else if (mode == 2 || mode == 5) CHECK(elapsed >= 0.5 && elapsed < 0.511);
            else CHECK(elapsed >= 0.025 && elapsed < 0.041);
            int previous_waits = waits;
            cleanup();
            CHECK(waits == previous_waits && terms == 1);
        }
    }
    puts("PASS: exited, graceful, forced, missing child and interrupted waits/sleeps");
#endif
    return 0;
}
C
flags=(-std=c23 -D_DEFAULT_SOURCE -O2 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" "$TMP/test.c" -o "$TMP/test"
"${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
if (( baseline )); then timeout 5 "$TMP/test" baseline; else timeout 5 "$TMP/test"; fi
"${CC:-cc}" "${flags[@]}" -DREAL_CHILD "$TMP/test.c" -o "$TMP/real"
timeout 5 "$TMP/real"
