#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure interrupted cold-sync preflight waits without a node or network.
# Usage: bash tools/scripts/fs_handshake_probe_interrupt_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=0 analyze=0
while [[ ${1:-} == --* ]]; do
    case $1 in
        --baseline) baseline=1 ;;
        --analyze) analyze=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
subject=${1:-$root/tools/fs_handshake_probe.c}
fixture=$(mktemp -d /tmp/zcl-probe-interrupt.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include "platform/socket_compat.h"
#include <stdlib.h>

#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)

static int64_t fixture_now;
static int opens, closes, waits, freed, interrupts, wait_error, pending_error;
static struct addrinfo addresses[2];
static int64_t fixture_clock(void) { return fixture_now; }
static int fixture_resolve(const char *host, const char *port,
                           const struct addrinfo *hints, struct addrinfo **out)
{
    (void)host; (void)port; (void)hints;
    *out = addresses;
    return 0;
}
static void fixture_free(struct addrinfo *out)
{
    CHECK(out == addresses);
    freed++;
}
static platform_socket_t fixture_open(int family, int type, int protocol,
                                      bool cloexec, bool nonblocking)
{
    (void)family; (void)type; (void)protocol;
    CHECK(cloexec && nonblocking);
    return 41 + ++opens;
}
static int fixture_connect(platform_socket_t fd, const struct sockaddr *addr,
                           socklen_t len)
{
    (void)addr; (void)len;
    CHECK(fd == 41 + opens);
    errno = EINPROGRESS;
    return -1;
}
static int fixture_close(platform_socket_t fd)
{
    CHECK(fd == 41 + opens);
    closes++;
    return 0;
}
static int fixture_wait(platform_socket_t fd, int ms)
{
    CHECK(fd == 41 + opens);
    CHECK(ms > 0 && ms == 2000 - fixture_now);
    waits++;
    /* The first endpoint becomes writable after a signal. A fallback
     * endpoint is silent and consumes whatever budget remains. */
    if (fd != 42) {
        fixture_now += ms;
        return 0;
    }
    if (interrupts > 0) {
        interrupts--;
        fixture_now += ms < 250 ? ms : 250;
        errno = EINTR;
        return -1;
    }
    if (wait_error) {
        errno = wait_error;
        return -1;
    }
    fixture_now += ms < 250 ? ms : 250;
    return 1;
}
static int fixture_pending(platform_socket_t fd, int *error)
{
    CHECK(fd == 42);
    *error = pending_error;
    return 0;
}

#define platform_time_monotonic_ms fixture_clock
#define getaddrinfo fixture_resolve
#define freeaddrinfo fixture_free
#define platform_socket_open fixture_open
#define platform_socket_connect fixture_connect
#define platform_socket_close fixture_close
#define platform_socket_wait_writable fixture_wait
#define platform_socket_pending_error fixture_pending
C
awk '/^static int probe_ms_left\(/ { copy = 1 }
     /^int main\(/ { copy = 0 }
     copy { print }' "$subject" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
static void reset(int signals, bool fallback)
{
    fixture_now = 1000;
    opens = closes = waits = freed = wait_error = pending_error = 0;
    interrupts = signals;
    memset(addresses, 0, sizeof(addresses));
    if (fallback) addresses[0].ai_next = &addresses[1];
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    reset(1, true);
    platform_socket_t fd = probe_connect("fixture", "1", 2000);
    printf("signal + silent fallback: connected=%d elapsed_ms=%lld opens=%d waits=%d\n",
           fd != PLATFORM_SOCKET_INVALID, (long long)(fixture_now - 1000), opens, waits);
    if (strcmp(argv[1], "1") == 0) return 0;
    CHECK(fd == 42 && fixture_now == 1500 && opens == 1 && closes == 0);
    CHECK(waits == 2 && freed == 1);

    reset(1, false);
    CHECK(probe_connect("fixture", "1", 2000) == 42);
    CHECK(fixture_now == 1500 && opens == 1 && waits == 2 && closes == 0);
    CHECK(freed == 1);

    /* Repeated signals cannot refresh the absolute deadline or start a
     * fallback connection once the budget has expired. */
    reset(10, true);
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    CHECK(fixture_now == 2000 && waits == 4 && opens == 1 && closes == 1);
    CHECK(freed == 1);

    reset(0, false);
    wait_error = EIO;
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    CHECK(waits == 1 && closes == 1 && freed == 1);

    reset(1, true);
    pending_error = ECONNREFUSED;
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    CHECK(waits == 3 && opens == 2 && closes == 2 && freed == 1);
    CHECK(fixture_now == 2000);

    reset(0, false);
    CHECK(probe_connect("fixture", "1", 2000) == 42);
    CHECK(waits == 1 && opens == 1 && closes == 0 && freed == 1);
    puts("PASS: signal retry, deadline, hard error, pending error, fallback, ordinary wait");
    return 0;
}
C
flags=(-std=c23 -O2 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L
       -I"$root/platform/modules/platform/include")
"${CC:-cc}" "${flags[@]}" "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 10 "$fixture/test" "$baseline"
