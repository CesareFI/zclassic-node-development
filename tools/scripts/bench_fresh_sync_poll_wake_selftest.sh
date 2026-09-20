#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Charge time outside nanosleep to the IBD observer's polling interval.
# Usage: bash tools/scripts/bench_fresh_sync_poll_wake_selftest.sh [--baseline] [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/zcl-poll-wake.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static double clock_sec, outside_sleep;
static int calls;
static double now_sec(void) { return clock_sec; }
static int fixture_sleep(const struct timespec *request, struct timespec *remain)
{
    CHECK(++calls < 100);
    CHECK(request->tv_sec >= 0 && request->tv_nsec >= 0 && request->tv_nsec < 1000000000);
    long long ns = request->tv_sec * 1000000000LL + request->tv_nsec;
    CHECK(ns > 0 && ns <= 2000000000LL);
    /* A handler or scheduler delay occurs after the kernel records remain.
     * Inject just one interruption so even an already-expired sleep can be
     * distinguished from an infinite signal stream. */
    if (calls == 1) {
        long long consumed = ns < 125000000 ? ns : 125000000;
        clock_sec += (double)consumed / 1e9 + outside_sleep;
        ns -= consumed;
        remain->tv_sec = (time_t)(ns / 1000000000);
        remain->tv_nsec = (long)(ns % 1000000000);
        errno = EINTR;
        return -1;
    }
    clock_sec += (double)ns / 1e9;
    return 0;
}
#define nanosleep fixture_sleep
static int poll_delay(double elapsed)
{
    enum { TIMEOUT = 30 };
C
awk '/\/\* 2 second poll/ { copy = 1; starts++ }
     copy && /^    }/ { copy = 0; ends++ }
     copy { print }
     END { if (starts != 1 || ends != 1) exit 1 }' "$subject" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
    return 0;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = argv[1][0] == '1';
    (void)now_sec;
    const double starts[] = {0, 29.5};
    const double delays[] = {0, 0.5, 5};
    for (size_t i = 0; i < sizeof(starts) / sizeof(starts[0]); i++) {
        for (size_t j = 0; j < sizeof(delays) / sizeof(delays[0]); j++) {
            calls = 0;
            clock_sec = starts[i];
            outside_sleep = delays[j];
            CHECK(poll_delay(starts[i]) == 0);
            double interval = i == 0 ? 2 : 0.5;
            double handler_end = 0.125 + outside_sleep;
            double expected = baseline ? interval + outside_sleep :
                              (handler_end > interval ? handler_end : interval);
            printf("start=%.3f outside_sleep=%.3f elapsed=%.3f sleeps=%d\n",
                   starts[i], outside_sleep, clock_sec - starts[i], calls);
            CHECK(clock_sec - starts[i] == expected);
            CHECK(calls == (!baseline && handler_end >= interval ? 1 : 2));
        }
    }
    puts(baseline ? "BASELINE: stale remaining interval extends observation delay" :
         "PASS: polling interval and final deadline include interruption overhead");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
"${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
timeout 5 "$fixture/test" "$baseline"
