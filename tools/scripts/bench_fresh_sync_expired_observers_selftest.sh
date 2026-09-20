#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure late-poll observer demand using the production loop and a fake clock.
# Usage: bash tools/scripts/bench_fresh_sync_expired_observers_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d /tmp/zcl-expired-observers.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#define TIMEOUT 30
#define HTTPSPORT 8447
#define WNOHANG 1
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static int g_child = 42;
static double clock_sec;
static int heights, scans, pages, states, scenario;
static double now_sec(void) { return clock_sec; }
static int waitpid(int pid, int *status, int flags)
{
    CHECK(pid == g_child && flags == WNOHANG);
    *status = 0;
    return 0;
}
static int fixture_system(const char *cmd)
{
    (void)cmd;
    CHECK(false);
    return 1;
}
#define system fixture_system
static int fixture_sleep(const struct timespec *req, struct timespec *rem)
{
    (void)req; (void)rem;
    CHECK(false); /* Each fixture expires within its first poll. */
    return -1;
}
#define nanosleep fixture_sleep
static bool rpc_call(const char *cookie, const char *method, char *buf, int size)
{
    CHECK(strcmp(cookie, "fixture") == 0);
    if (strcmp(method, "syncstate") == 0) {
        CHECK(++states == 1);
        clock_sec += 2;
        CHECK(snprintf(buf, (size_t)size, "{\"state\":\"at_tip\"}") < size);
        return scenario != 4;
    }
    CHECK(strcmp(method, "getblockcount") == 0);
    heights++;
    clock_sec += 2;
    CHECK(snprintf(buf, (size_t)size, "{\"result\":123}") < size);
    return true;
}
static bool explorer_responding(void)
{
    pages++;
    clock_sec += 2;
    return false;
}
static void snapshot_log_summary(const char *path, char *buf, size_t size)
{
    (void)path; (void)buf; (void)size;
    CHECK(false); /* No phase markers in the fixture log. */
}
C
awk '/^static bool json_get_str\(/ { copy = 1 }
     /^static const char \*const phase_markers/ { copy = 0 }
     /^struct phase_log \{/ { copy = 1 }
     /^\/\* One bounded pass/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
static bool phase_log_poll(FILE *f, struct phase_log *log)
{
    CHECK(f != NULL && log != NULL);
    scans++;
    clock_sec += 2;
    return true;
}
static int observe(int mode, bool baseline, const char *logfile)
{
    /* Expire during state, height or log; also test exact deadline and a
     * failed state RPC. Observer costs are deterministic simulated seconds. */
    const double starts[] = {29, 27, 25, 28, 29};
    const int expected_heights[] = {0, 1, 1, 1, 0};
    const int expected_scans[] = {0, 0, 1, 0, 0};
    scenario = mode;
    clock_sec = 100 + starts[mode];
    heights = scans = pages = states = 0;
    const double t0 = 100;
    const char *cookie = "fixture";
C
awk '/^    \/\* Phase timestamps \*\// { copy = 1 }
     copy && (/^    benchmark_results\(/ || /^    printf\("\\n"\);/) { exit }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
    printf("scenario=%d start=%.1f height=%d scans=%d pages=%d finish=%.1f\n",
           mode, starts[mode], heights, scans, pages, clock_sec - t0);
    CHECK(t_done == 0 && t_explorer == 0);
    CHECK(t_tip == (mode == 4 ? 0 : starts[mode] + 2));
    CHECK(heights == (baseline ? 1 : expected_heights[mode]));
    CHECK(scans == (baseline ? 1 : expected_scans[mode]));
    CHECK(pages == (baseline && mode != 4 ? 1 : 0));
    CHECK(clock_sec - t0 == starts[mode] + 2 + 2 * (heights + scans + pages));
    return 0;
}
int main(int argc, char **argv)
{
    CHECK(argc == 3);
    for (int mode = 0; mode < 5; mode++)
        CHECK(observe(mode, argv[1][0] == '1', argv[2]) == 0);
    puts("PASS: expired observer demand, missing state, exact deadline, preserved tip timestamps, incomplete outcome");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
: > "$fixture/node.log"
timeout 5 "$fixture/test" "$baseline" "$fixture/node.log"
