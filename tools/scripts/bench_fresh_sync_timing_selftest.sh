#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Run the production polling loop with a deterministic clock and observers.
# No node, network, wallet, credentials or production datadir participate.
# Usage: bash tools/scripts/bench_fresh_sync_timing_selftest.sh [--analyze] [source.c]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
analyze=false
if [ "${1:-}" = --analyze ]; then analyze=true; shift; fi
SOURCE="${1:-$ROOT/tools/bench_fresh_sync.c}"
TMP="$(mktemp -d /tmp/zcl-bench-timing.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
#define TIMEOUT 30
#define HTTPSPORT 8447
#define WNOHANG 1
static int g_child = 42;
static double clock_sec;
static int scenario, state_calls, height_calls, explorer_calls, log_calls;
static int height_latency;
static double last_state_observed;
static double now_sec(void) { return clock_sec; }
static int fixture_system(const char *cmd)
{
    (void)cmd;
    CHECK(false); /* No diagnostic subprocess is expected in these cases. */
    return 1;
}
#define system fixture_system
static int waitpid(int pid, int *status, int flags)
{
    CHECK(pid == 42 && flags == WNOHANG);
    *status = 0;
    return 0;
}
static int fixture_nanosleep(const struct timespec *request, struct timespec *remain)
{
    CHECK(request->tv_sec == 2 && request->tv_nsec == 0 && remain != NULL);
    clock_sec += 2;
    return 0;
}
#define nanosleep fixture_nanosleep
static bool rpc_call(const char *cookie, const char *method, char *buf, int size)
{
    CHECK(strcmp(cookie, "fixture") == 0);
    if (strcmp(method, "syncstate") == 0) {
        clock_sec += 1;
        last_state_observed = clock_sec - 100;
        state_calls++;
        if (scenario == 1 && state_calls == 1) {
            buf[0] = '\0';
            return false;
        }
        CHECK(snprintf(buf, (size_t)size, "{\"state\":\"at_tip\"}") < size);
    } else {
        CHECK(strcmp(method, "getblockcount") == 0);
        height_calls++;
        clock_sec += height_latency;
        CHECK(snprintf(buf, (size_t)size, "{\"result\":123}") < size);
    }
    return true;
}
static bool explorer_responding(void)
{
    clock_sec += 2;
    explorer_calls++;
    return scenario != 2 || explorer_calls > 1;
}
static int run_cmd(const char *cmd, char *buf, int size)
{
    CHECK(strstr(cmd, "UTXOs in") != NULL && size > 0);
    buf[0] = '\0';
    return 0;
}
#define snapshot_log_summary(path, buf, size) run_cmd("UTXOs in", buf, (int)(size))
C
# Compile the real parsers, phase state and main polling loop. Delimiters make
# a moved/removed loop a compiler failure, rather than testing a copied model.
awk '/^static bool json_get_str\(/ { copy = 1 }
     /^static const char \*const phase_markers/ { copy = 0 }
     /^struct phase_log \{/ { copy = 1 }
     /^\/\* One bounded pass/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
static bool phase_log_poll(FILE *f, struct phase_log *log)
{
    CHECK(f != NULL);
    clock_sec += 1;
    log_calls++;
    for (int i = 0; i < LOG_PHASE_COUNT; i++) log->seen[i] = true;
    return true;
}
static int run_fixture(int mode, int latency, const char *logfile)
{
    scenario = mode;
    height_latency = latency;
    state_calls = height_calls = explorer_calls = log_calls = 0;
    clock_sec = 110;
    const double t0 = 100;
    const char *cookie = "fixture";
C
awk '/^    \/\* Phase timestamps \*\// { copy = 1 }
     copy && /^    benchmark_results\(/ { exit }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
    printf("fixture=%d height_latency=%d height_calls=%d tip=%.1f explorer=%.1f done=%.1f phase=%.1f\n",
           mode, latency, height_calls, t_tip, t_explorer, t_done, t_fc);
    double phase_time = 12 + (mode == 1 ? 0 : latency);
    CHECK(t_filesync == phase_time && t_filesync_done == phase_time && t_fc == phase_time);
    CHECK(t_snap_start == phase_time && t_snap_end == phase_time);
    CHECK(log_calls == 1);
    /* Height is observed only on transitions, never during stable tip polls.
     * Keep exact demand assertions alongside the observation timestamps. */
    CHECK(height_calls == 1);
    if (mode == 0) {
        CHECK(t_tip == 11 && t_explorer == 14 + latency && t_done == 17 + latency);
        CHECK(state_calls == 2 && explorer_calls == 1);
    } else if (mode == 1) {
        /* Missing first state must not become an early tip timestamp. */
        CHECK(t_tip == 15 && t_explorer == 17 + latency);
        /* At zero height latency poll three is exactly five seconds after
         * first tip. It must wait for poll four: grace is strictly > 5. */
        CHECK(t_done == (latency == 0 ? 23 : 20 + latency));
        CHECK(state_calls == (latency == 0 ? 4 : 3) && explorer_calls == 1);
    } else {
        /* Failed first explorer observation must retain the later time. */
        CHECK(t_tip == 11 && t_explorer == 19 + latency && t_done == 19 + latency);
        CHECK(state_calls == 2 && explorer_calls == 2);
    }
    CHECK(t_done - t_tip > 5);
    CHECK(last_state_observed - t_tip > 5);
    CHECK(t_done == now_sec() - t0);
    return 0;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    const int latencies[] = {0, 2, 3};
    for (size_t i = 0; i < sizeof(latencies) / sizeof(latencies[0]); i++)
        for (int mode = 0; mode < 3; mode++)
            CHECK(run_fixture(mode, latencies[i], argv[1]) == 0);
    puts("PASS: nine timing scenarios, exact RPC demand, missing samples, strict grace boundary, first observations");
    return 0;
}
C
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror "$TMP/test.c" -o "$TMP/test"
if "$analyze"; then
    "${CC:-cc}" -std=c23 -Wall -Wextra -Werror -fanalyzer \
        -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
: > "$TMP/node.log"
timeout 5 "$TMP/test" "$TMP/node.log"
