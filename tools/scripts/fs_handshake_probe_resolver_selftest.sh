#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Cold-sync preflight must not resolve a host after its budget expires.
# Usage: bash tools/scripts/fs_handshake_probe_resolver_selftest.sh [--baseline] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
source_file=${1:-$root/tools/fs_handshake_probe.c}
fixture=$(mktemp -d /tmp/zcl-probe-resolver.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include "platform/socket_compat.h"
#include <stdlib.h>

#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static int64_t fixture_now;
static int resolves, opens, freed, delay_ms, resolve_error;
static struct addrinfo address;
static int64_t fixture_clock(void) { return fixture_now; }
static int fixture_resolve(const char *host, const char *port,
                           const struct addrinfo *hints, struct addrinfo **out)
{
    CHECK(strcmp(host, "fixture") == 0 && strcmp(port, "1") == 0);
    CHECK(hints->ai_family == AF_UNSPEC && hints->ai_socktype == SOCK_STREAM);
    resolves++;
    fixture_now += delay_ms;
    *out = resolve_error ? NULL : &address;
    return resolve_error;
}
static void fixture_free(struct addrinfo *out)
{
    CHECK(out == &address);
    freed++;
}
static platform_socket_t fixture_open(int family, int type, int protocol,
                                      bool cloexec, bool nonblocking)
{
    (void)family; (void)type; (void)protocol;
    CHECK(cloexec && nonblocking);
    opens++;
    return PLATFORM_SOCKET_INVALID; /* Never open a real socket. */
}
#define platform_time_monotonic_ms fixture_clock
#define getaddrinfo fixture_resolve
#define freeaddrinfo fixture_free
#define platform_socket_open fixture_open
C
awk '/^static int probe_ms_left\(/ { copy = 1 }
     /^int main\(/ { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
static void reset(int delay)
{
    fixture_now = 1000;
    resolves = opens = freed = resolve_error = 0;
    delay_ms = delay;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    reset(4000);
    CHECK(probe_connect("fixture", "1", 1000) == PLATFORM_SOCKET_INVALID);
    printf("expired probe: resolver_calls=%d added_ms=%lld sockets=%d\n",
           resolves, (long long)(fixture_now - 1000), opens);
    if (strcmp(argv[1], "1") == 0) return 0;
    CHECK(resolves == 0 && fixture_now == 1000 && opens == 0 && freed == 0);
    reset(4000);
    CHECK(probe_connect("fixture", "1", 999) == PLATFORM_SOCKET_INVALID);
    CHECK(resolves == 0 && fixture_now == 1000 && opens == 0 && freed == 0);

    /* A still-live budget admits resolution. Time spent resolving is not
     * granted again to socket work; this test does not bound active DNS. */
    reset(4000);
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    CHECK(resolves == 1 && fixture_now == 5000 && opens == 0 && freed == 1);
    reset(1000);
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    CHECK(resolves == 1 && opens == 0 && freed == 1);
    reset(0);
    CHECK(probe_connect("fixture", "1", 1001) == PLATFORM_SOCKET_INVALID);
    CHECK(resolves == 1 && opens == 1 && freed == 1);
    reset(0);
    resolve_error = EAI_FAIL;
    CHECK(probe_connect("fixture", "1", 2000) == PLATFORM_SOCKET_INVALID);
    CHECK(resolves == 1 && opens == 0 && freed == 0);
    puts("PASS: expired admission, resolver delay, live budget, resolution error");
    return 0;
}
C
flags=(-std=c23 -O2 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L
       -I"$root/platform/modules/platform/include")
"${CC:-cc}" "${flags[@]}" "$fixture/test.c" -o "$fixture/test"
if [[ ${ANALYZE:-0} == 1 ]]; then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
"$fixture/test" "$baseline"
