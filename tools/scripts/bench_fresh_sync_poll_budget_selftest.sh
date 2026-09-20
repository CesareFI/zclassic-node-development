#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise the production IBD deadline and sleep against a deterministic clock.
# Usage: bash tools/scripts/bench_fresh_sync_poll_budget_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
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
fixture=$(mktemp -d /tmp/zcl-poll-budget.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#define TIMEOUT 30
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static double clock_sec;
static int polls, sleeps;
static bool interrupt_sleep;
static double now_sec(void) { return 100 + clock_sec; }
static int fixture_sleep(const struct timespec *request, struct timespec *remain)
{
    CHECK(++sleeps <= 100);
    CHECK(request->tv_sec >= 0 && request->tv_nsec >= 0 && request->tv_nsec < 1000000000);
    CHECK(remain != NULL);
    long long ns = request->tv_sec * 1000000000LL + request->tv_nsec;
    CHECK(ns <= 2000000000LL);
    if (interrupt_sleep && ns > 62500000) {
        clock_sec += 0.0625;
        ns -= 62500000;
        remain->tv_sec = (time_t)(ns / 1000000000);
        remain->tv_nsec = (long)(ns % 1000000000);
        errno = EINTR;
        return -1;
    }
    clock_sec += (double)ns / 1e9;
    return 0;
}
#define nanosleep fixture_sleep
static int observe(void)
{
    const double t0 = 100;
C
# Extract the actual loop entry and final sleep. Missing delimiters fail
# compilation or the exact poll/sleep counts; no copied deadline predicate.
awk '/^    while \(1\)/ { copy = 1 }
     copy && /\/\* Check child alive/ { exit }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
        CHECK(++polls <= 4);
C
awk '/\/\* 2 second poll/ { copy = 1 }
     copy && /^    }/ { print; exit }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
    return 0;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = argv[1][0] == '1';
    const double starts[] = {27, 28, 29, 29.875, 30, 30.25};
    const int expected_polls[] = {2, 1, 1, 1, 0, 0};
    const int baseline_polls[] = {2, 2, 1, 1, 1, 0};
    for (int interrupted = 0; interrupted < 2; interrupted++) {
        interrupt_sleep = interrupted != 0;
        for (size_t i = 0; i < sizeof(starts) / sizeof(starts[0]); i++) {
            polls = sleeps = 0;
            clock_sec = starts[i];
            CHECK(observe() == 0);
            printf("start=%.3f interrupted=%d polls=%d finish=%.3f overrun=%.3f\n",
                   starts[i], interrupted, polls, clock_sec,
                   clock_sec - (starts[i] > TIMEOUT ? starts[i] : TIMEOUT));
            CHECK(polls == (baseline ? baseline_polls[i] : expected_polls[i]));
            double expected_end = baseline ? starts[i] + 2 * baseline_polls[i] :
                                  (starts[i] > TIMEOUT ? starts[i] : TIMEOUT);
            CHECK(clock_sec == expected_end);
            CHECK((polls == 0) == (sleeps == 0));
        }
    }
    puts(baseline ? "PASS: baseline deadline-overrun characterization" :
         "PASS: twelve deadline cases, fractional remainder, interrupted sleeps, no post-deadline polls");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 5 "$fixture/test" "$baseline"
