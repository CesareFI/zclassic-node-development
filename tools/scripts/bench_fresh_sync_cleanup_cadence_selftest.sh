#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Count teardown observations under frequent signals; no node or real signals.
# Usage: bash tools/scripts/bench_fresh_sync_cleanup_cadence_selftest.sh [--baseline] [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
source_file=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-cleanup-cadence.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static pid_t g_child = 42;
static long long elapsed_ns;
static int mode, polls, sleeps, terms, kills;
static bool reaped;
static double now_sec(void) { return (double)elapsed_ns / 1e9; }
static int fixture_kill(pid_t child, int sig)
{
    CHECK(child == 42 && !reaped);
    if (sig == SIGTERM) terms++;
    else { CHECK(sig == SIGKILL && elapsed_ns >= 500000000); kills++; }
    return 0;
}
static pid_t fixture_wait(pid_t child, int *status, int flags)
{
    CHECK(child == 42 && !reaped);
    *status = 0;
    if (flags == WNOHANG) polls++;
    else CHECK(kills == 1);
    if (kills || (mode == 2 && elapsed_ns >= 25000000)) {
        reaped = true;
        return child;
    }
    return 0;
}
static int fixture_sleep(const struct timespec *request, struct timespec *remaining)
{
    (void)remaining;
    CHECK(++sleeps < 10000);
    CHECK(request->tv_sec == 0 && request->tv_nsec == 10000000);
    if (mode == 0) { elapsed_ns += request->tv_nsec; return 0; }
    /* The fourth case charges a slow signal handler to the grace deadline. */
    elapsed_ns += mode == 3 ? 200000000 : 100000;
    errno = EINTR;
    return -1;
}
#define kill fixture_kill
#define waitpid fixture_wait
#define nanosleep fixture_sleep
C
awk '/^static void cleanup\(/ { copy = 1; starts++ }
     copy && /^static double now_sec\(/ { copy = 0; ends++ }
     copy { print }
     END { if (starts != 1 || ends != 1) exit 1 }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = argv[1][0] == '1';
    for (mode = 0; mode < 4; mode++) {
        elapsed_ns = 0;
        polls = sleeps = terms = kills = 0;
        reaped = false;
        g_child = 42;
        cleanup();
        printf("mode=%d seconds=%.6f child_polls=%d sleeps=%d forced=%d\n",
               mode, now_sec(), polls, sleeps, kills);
        CHECK(terms == 1 && reaped && g_child == 0);
        CHECK(kills == (mode == 2 ? 0 : 1));
        if (mode == 2) CHECK(elapsed_ns >= 25000000 && elapsed_ns <= 41000000);
        else if (mode == 3) CHECK(elapsed_ns == 600000000 && polls == 4);
        else CHECK(elapsed_ns >= 500000000 && elapsed_ns <= 510000000);
        if (!baseline) CHECK(polls <= (mode == 2 ? 5 : 52));
        int old_polls = polls;
        cleanup();
        CHECK(polls == old_polls && terms == 1);
    }
    puts(baseline ? "BASELINE: shutdown observer work measured" :
         "PASS: bounded child polling, graceful exit, forced grace, slow handlers, repeat cleanup");
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
"${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
timeout 5 "$fixture/test" "$baseline"
