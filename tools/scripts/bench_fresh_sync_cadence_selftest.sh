#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure interrupted IBD poll cadence with a deterministic sleep fixture.
# Usage: bash tools/scripts/bench_fresh_sync_cadence_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
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
fixture=$(mktemp -d /tmp/zcl-poll-cadence.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static long long elapsed_ns;
static int calls, interruptions, mode;
static double now_sec(void) { return (double)elapsed_ns / 1e9; }
static int fixture_sleep(const struct timespec *request, struct timespec *remain)
{
    CHECK(++calls <= 1000);
    CHECK(request->tv_sec >= 0 && request->tv_nsec >= 0 && request->tv_nsec < 1000000000);
    long long duration = request->tv_sec * 1000000000LL + request->tv_nsec;
    CHECK(duration <= 2000000000LL);
    if (mode == 2) { errno = EINVAL; return -1; }
    if (mode == 1 && duration > 125000000) {
        elapsed_ns += 125000000;
        duration -= 125000000;
        if (remain) {
            remain->tv_sec = (time_t)(duration / 1000000000);
            remain->tv_nsec = (long)(duration % 1000000000);
        }
        interruptions++;
        errno = EINTR;
        return -1;
    }
    elapsed_ns += duration;
    return 0;
}
static int fixture_usleep(unsigned int usec)
{
    struct timespec request = {usec / 1000000, (usec % 1000000) * 1000L};
    return fixture_sleep(&request, NULL);
}
#define usleep fixture_usleep
#define nanosleep fixture_sleep
static int poll_delay(void)
{
    enum { TIMEOUT = 1800 };
    const double elapsed = 0;
    (void)elapsed;
C
# Include the real delay at the end of the main observation loop, with a
# sentinel so missing extraction cannot silently pass the no-signal case.
awk '/usleep\(2000000\)/ || /\/\* 2 second poll/ { copy = 1 }
     copy && /^    }/ { exit }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
    return 0;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = argv[1][0] == '1';
    (void)fixture_usleep;
    (void)now_sec;
    for (mode = 0; mode < 3; mode++) {
        elapsed_ns = 0;
        calls = interruptions = 0;
        int polls;
        for (polls = 0; polls < 20; polls++) {
            int result = poll_delay();
            if (mode == 2 && !baseline) { CHECK(result == 1); break; }
            CHECK(result == 0);
        }
        printf("mode=%d polls=%d sleeps=%d interruptions=%d elapsed_seconds=%.3f\n",
               mode, polls, calls, interruptions, (double)elapsed_ns / 1e9);
        if (mode == 0) CHECK(elapsed_ns == 40000000000LL && calls == 20);
        if (mode == 1) {
            CHECK(elapsed_ns == (baseline ? 2500000000LL : 40000000000LL));
            CHECK(interruptions == (baseline ? 20 : 300));
        }
        if (mode == 2) CHECK(calls == (baseline ? 20 : 1));
    }
    puts("PASS: normal cadence, interrupted cadence, permanent sleep failure");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 5 "$fixture/test" "$baseline"
