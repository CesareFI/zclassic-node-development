#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Deterministic cold-sync preflight deadline test; no node or network needed.
# Usage: bash tools/scripts/fs_handshake_probe_deadline_selftest.sh [source.c]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${1:-$ROOT/tools/fs_handshake_probe.c}"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/zcl-fs-probe-deadline.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT

cat > "$FIXTURE/test.c" <<'EOF'
#include "platform/socket_compat.h"
#include <stdlib.h>

#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)

static int64_t fixture_now;
static int setup_ms, connect_result, wait_result, pending_error;
static int opens, closes, waits, last_wait, freed;
static struct addrinfo address[2];

static int64_t fixture_clock(void) { return fixture_now; }
static int fixture_resolve(const char *host, const char *port,
                           const struct addrinfo *hints, struct addrinfo **out)
{
    (void)host; (void)port; (void)hints;
    *out = address;
    return 0;
}
static void fixture_free(struct addrinfo *out)
{
    CHECK(out == address);
    freed++;
}
static platform_socket_t fixture_open(int domain, int type, int protocol,
                                      bool cloexec, bool nonblocking)
{
    (void)domain; (void)type; (void)protocol;
    CHECK(cloexec && nonblocking);
    opens++;
    return 42;
}
static int fixture_connect(platform_socket_t fd, const struct sockaddr *addr,
                           socklen_t len)
{
    CHECK(fd == 42);
    (void)addr; (void)len;
    fixture_now += setup_ms;
    errno = EINPROGRESS;
    return connect_result;
}
static int fixture_close(platform_socket_t fd)
{
    CHECK(fd == 42);
    closes++;
    return 0;
}
static int fixture_wait(platform_socket_t fd, int ms)
{
    CHECK(fd == 42 && ms > 0);
    waits++;
    last_wait = ms;
    if (wait_result == 0) fixture_now += ms;
    return wait_result;
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
EOF
# Compile the actual production helpers, retaining the real platform types.
awk '/^static int probe_ms_left\(/ { copy = 1 }
     /^int main\(/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$FIXTURE/test.c"
cat >> "$FIXTURE/test.c" <<'EOF'
static void reset(int delay)
{
    fixture_now = 1000;
    setup_ms = delay;
    connect_result = -1;
    wait_result = pending_error = 0;
    opens = closes = waits = last_wait = freed = 0;
    memset(address, 0, sizeof(address));
}

int main(void)
{
    reset(750);
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    printf("1000 ms budget, 750 ms setup: wait=%d ms, elapsed=%lld ms\n",
           last_wait, (long long)(fixture_now - 1000));
    CHECK(last_wait == 250 && fixture_now == 2000);
    CHECK(opens == 1 && closes == 1 && waits == 1 && freed == 1);

    reset(1000);
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    CHECK(waits == 0 && closes == 1 && freed == 1);
    reset(1200);
    address[0].ai_next = &address[1];
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    CHECK(opens == 1 && waits == 0 && closes == 1 && freed == 1);

    reset(0);
    CHECK(probe_connect("fixture", "1", 1000) == PLATFORM_SOCKET_INVALID);
    CHECK(opens == 0 && waits == 0 && freed == 0);
    CHECK(probe_ms_left(999) == 0);
    CHECK(probe_ms_left(1001) == 1);
    CHECK(probe_ms_left(INT64_MAX) == INT32_MAX);

    reset(0);
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    CHECK(last_wait == 1000 && fixture_now == 2000 && closes == 1);
    reset(250);
    wait_result = 1;
    CHECK(probe_connect("fixture", "1", 2000) == 42);
    CHECK(last_wait == 750 && closes == 0 && freed == 1);

    reset(250);
    connect_result = 0;
    CHECK(probe_connect("fixture", "1", 2000) == 42);
    CHECK(waits == 0 && closes == 0 && freed == 1);

    reset(250);
    wait_result = 1;
    pending_error = ECONNREFUSED;
    address[0].ai_next = &address[1];
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    CHECK(opens == 2 && closes == 2 && waits == 2 && freed == 1);
    CHECK(last_wait == 500);
    puts("PASS: remaining budget, expiry, cleanup, connect results, address fallback");
    return 0;
}
EOF
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror -pedantic \
    -D_POSIX_C_SOURCE=200809L -I"$ROOT/platform/modules/platform/include" \
    "$FIXTURE/test.c" -o "$FIXTURE/test"
"$FIXTURE/test"
