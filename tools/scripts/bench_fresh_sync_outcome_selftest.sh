#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Compile the production poll loop and result path against a deterministic clock.
# No node, network, credentials or datadir is used.
# Usage: bash tools/scripts/bench_fresh_sync_outcome_selftest.sh [--analyze] [source.c]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
analyze=false
if [ "${1:-}" = --analyze ]; then analyze=true; shift; fi
SOURCE="${1:-$ROOT/tools/bench_fresh_sync.c}"
TMP="$(mktemp -d /tmp/zcl-bench-outcome.XXXXXX)"
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
static int scenario, state_calls, explorer_calls, page_calls;
static double now_sec(void) { return clock_sec; }
static int fixture_system(const char *cmd)
{
    (void)cmd;
    CHECK(false);
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
    double delay = request->tv_sec + (double)request->tv_nsec / 1e9;
    double remaining = 130 - clock_sec;
    CHECK(delay == (remaining < 2 ? remaining : 2) && remain != NULL);
    clock_sec += delay;
    return 0;
}
#define nanosleep fixture_nanosleep
static bool rpc_call(const char *cookie, const char *method, char *buf, int size)
{
    CHECK(strcmp(cookie, "fixture") == 0);
    if (strcmp(method, "validationstatus") == 0) {
        /* Successful diagnostics must not turn a failed run into success. */
        CHECK(snprintf(buf, (size_t)size,
              "{\"state\":\"validating\",\"verified_height\":1,\"proofs_verified\":1}") < size);
        return true;
    }
    if (strcmp(method, "syncstate") == 0) {
        state_calls++;
        if (scenario == 4) clock_sec = 131; /* First tip read arrives late. */
        if (scenario == 5 && state_calls > 1) clock_sec = 130;
        /* Losing tip or losing the observation must break the grace period.
         * Scenarios 7/9 recover on poll four; 10 recovers too near deadline. */
        bool gap = state_calls > 1 &&
                   (scenario == 6 || scenario == 8 || scenario == 19 || scenario == 21 ||
                    ((scenario == 7 || scenario == 9) && state_calls < 4) ||
                    ((scenario == 20 || scenario == 22) && state_calls < 4) ||
                    (scenario == 10 && clock_sec < 128));
        if (gap && (scenario == 8 || scenario == 9 || scenario == 21 || scenario == 22))
            return false;
        const char *format = "{\"state\":\"%s\"}";
        if (scenario == 13) format = "{\"state\": \"%s\"}";
        if (scenario == 14) format = "{\"state\" :\"%s\"}";
        if (scenario == 15) format = "{\n\t\"state\"\r\n : \t\r\n\"%s\"\n}";
        if (scenario == 16) format = "{\"state\" \"%s\"}"; /* Missing colon. */
        if (scenario == 17) format = "{\"state\": %s}"; /* Not a string. */
        if (scenario == 18) format = "{\"label\":\"state\",\"state\":\"%s\"}";
        CHECK(snprintf(buf, (size_t)size, format,
                       scenario == 1 || gap ? "syncing" : "at_tip") < size);
    } else {
        CHECK(strcmp(method, "getblockcount") == 0);
        CHECK(snprintf(buf, (size_t)size, "{\"result\":123}") < size);
    }
    return true;
}
static bool explorer_responding(void)
{
    explorer_calls++;
    if (scenario == 19 || scenario == 21) return false;
    /* Ready during the gap, but first probed again upon a fresh tip sample. */
    if (scenario == 20 || scenario == 22) return state_calls >= 2;
    if (scenario == 23) return state_calls >= 4;
    if (scenario == 11) clock_sec = 117; /* Slow first explorer observation. */
    if (scenario == 3 && state_calls > 1) clock_sec = 131;
    if ((scenario == 5 || scenario == 12) && state_calls > 1) clock_sec = 130;
    if ((scenario == 3 || scenario == 5 || scenario == 12) && state_calls == 1)
        return false;
    return scenario != 2;
}
static int explorer_page_size(const char *path)
{
    (void)path;
    page_calls++;
    return 2048;
}
static int run_cmd(const char *cmd, char *buf, int size)
{
    CHECK(strstr(cmd, "UTXOs in") != NULL && size > 0);
    buf[0] = '\0';
    return 0;
}
#define snapshot_log_summary(path, buf, size) run_cmd("UTXOs in", buf, (int)(size))
C
awk '/^static bool json_get_str\(/ { copy = 1 }
     /^static const char \*const phase_markers/ { copy = 0 }
     /^struct phase_log \{/ { copy = 1 }
     /^\/\* One bounded pass/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
awk '/^static void benchmark_results\(/ { copy = 1; starts++ }
     /^static bool benchmark_progress_output\(/ { copy = 0; ends++ }
     copy { print }
     END { if (starts != 1 || ends != 1) exit 1 }' "$SOURCE" >> "$TMP/test.c"
sed -n '/^static void benchmark_validation(/,/^}/p' "$SOURCE" >> "$TMP/test.c"
sed -n '/^static int benchmark_outcome(/,/^}/p' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
static bool phase_log_poll(FILE *f, struct phase_log *log)
{
    CHECK(f != NULL);
    for (int i = 0; i < LOG_PHASE_COUNT; i++) log->seen[i] = true;
    return true;
}
static int run_fixture(const char *logfile)
{
    const double t0 = 100;
    const char *cookie = "fixture", *datadir = "unused-fixture";
C
# Include the real result printing and final return, as well as the poll loop.
awk '/^    \/\* Phase timestamps \*\// { copy = 1 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
int main(int argc, char **argv)
{
    CHECK(argc == 3);
    scenario = atoi(argv[2]);
    clock_sec = scenario == 3 || scenario == 5 || scenario == 12 ? 123 : 110;
    int rc = run_fixture(argv[1]);
    bool expected_success = scenario == 0 || scenario == 5 ||
                            scenario == 7 || scenario == 9 || scenario == 11 ||
                            (scenario >= 13 && scenario <= 15) || scenario == 18 ||
                            scenario == 20 || scenario == 22 || scenario == 23;
    printf("fixture=%d exit=%d expected_success=%d polls=%d\n",
           scenario, rc, expected_success, state_calls);
    CHECK((rc == 0) == expected_success);
    CHECK(page_calls == (expected_success ? 4 : 0));
    if (scenario == 7 || scenario == 9) CHECK(clock_sec == 122);
    if (scenario == 11) CHECK(clock_sec == 119 && state_calls == 2);
    if ((scenario >= 13 && scenario <= 15) || scenario == 18)
        CHECK(clock_sec == 116 && state_calls == 4);
    if (scenario >= 19) {
        printf("explorer_demand scenario=%d polls=%d requests=%d elapsed=%.0f\n",
               scenario, state_calls, explorer_calls, clock_sec - 100);
        if (scenario == 19 || scenario == 21) {
            CHECK(state_calls == 10 && clock_sec == 130);
            CHECK(explorer_calls == 1);
        } else if (scenario == 20 || scenario == 22) {
            CHECK(state_calls == 7 && clock_sec == 122);
            CHECK(explorer_calls == 2);
        } else {
            CHECK(state_calls == 4 && clock_sec == 116);
            CHECK(explorer_calls == 4);
        }
    }
    if (scenario == 1) CHECK(explorer_calls == 0);
    if (scenario == 2) CHECK(explorer_calls == 10);
    return 0;
}
C
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror "$TMP/test.c" -o "$TMP/test"
if "$analyze"; then
    "${CC:-cc}" -std=c23 -Wall -Wextra -Werror -fanalyzer \
        -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
: > "$TMP/node.log"
failures=0
for mode in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23; do
    rc=0
    timeout 5 "$TMP/test" "$TMP/node.log" "$mode" > "$TMP/output" 2>&1 || rc=$?
    case "$mode" in
        0|5|7|9|11|13|14|15|18|20|22|23) expected=1 ;;
        *) expected=0 ;;
    esac
    count=$(grep -c 'Fully operational' "$TMP/output" || true)
    if [[ "$rc" != 0 || "$count" != "$expected" ]]; then
        cat "$TMP/output" >&2
        printf 'FAIL: scenario %s rc=%s completion_reports=%s expected=%s\n' \
            "$mode" "$rc" "$count" "$expected" >&2
        failures=$((failures + 1))
    else
        printf 'PASS: scenario %s completion_reports=%s\n' "$mode" "$count"
        if (( mode >= 19 )); then grep '^explorer_demand ' "$TMP/output"; fi
    fi
    if [[ "$mode" == 7 || "$mode" == 9 || "$mode" == 20 || "$mode" == 22 ]]; then
        # The first tip timestamp remains 10 s; recovery completes at 22 s.
        if ! grep -Eq 'Synced to tip: +10\.0s' "$TMP/output" ||
           ! grep -Eq 'Total cold->live: +22\.0s' "$TMP/output"; then
            echo "FAIL: first-tip/recovered completion timestamps mode=$mode" >&2
            failures=$((failures + 1))
        fi
    fi
    if [[ "$mode" == 20 || "$mode" == 22 ]]; then
        if ! grep -Eq 'Explorer serving: +16\.0s' "$TMP/output"; then
            echo "FAIL: explorer observed during tip gap mode=$mode" >&2
            failures=$((failures + 1))
        fi
    fi
done
[[ "$failures" == 0 ]] || exit 1
printf 'PASS: deadlines, consecutive tip observations, loss/recovery and first-tip timestamp\n'
