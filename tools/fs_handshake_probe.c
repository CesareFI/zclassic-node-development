/* Copyright 2026 Rhett Creighton - Apache License 2.0
 *
 * fs_handshake_probe — the PRE-FLIGHT fixture-compatibility probe for the
 * C3 cold-sync stopwatch (tools/scripts/cold_start_to_tip_stopwatch.sh).
 *
 * The measured incident this exists to catch in seconds instead of after
 * the full 600s budget: the stopwatch's serving fixture peer ran a binary
 * that PREDATED the authenticated X25519/HKDF file-service handshake
 * (d1db47aee7, core/modules/net/src/file_service_handshake.c). The
 * harness's file-peer precheck was a bare TCP connect, which the stale
 * fixture passed; the wiped node's boot then logged
 * "rom_fetch_get_directory(): directory: handshake failed ... — skipping
 * seed" (core/modules/net/src/rom_fetch_directory.c:134), fell back to
 * from-genesis IBD, and every scheduled run burned its whole budget on a
 * measurement that could never pass.
 *
 * This probe performs the CLIENT half of the exact handshake the wiped
 * node's RLS directory fetch performs — fs_handshake_until() with the
 * all-zero UTXO root, initiator role, ONE absolute deadline — against the
 * stated file peer, and reports the outcome as an exit code:
 *
 *   0  handshake_ok      the peer completed the authenticated file-service
 *                        handshake (a compatible fixture)
 *   3  unreachable       TCP connect failed, was refused, or timed out
 *   4  handshake_failed  the peer accepted but could not complete the
 *                        handshake — a pre-handshake (legacy) binary, a
 *                        non-file-service listener, or a silent peer
 *   2  usage error
 *
 * Read-only against the peer: the wire exchange is two 32-byte ephemeral
 * public keys plus two 32-byte key confirmations; no frame is ever
 * requested, so the serving side only sees a session that closes right
 * after key confirmation.
 *
 * The session struct is initialised inline (memset + fd + start stamp +
 * TCP_NODELAY) rather than by linking fs_session_init()'s home TU
 * (core/modules/net/src/file_service_transport.c): that TU is the frame
 * codec and would drag the x4 SHA3 lanes and the checked-alloc module into
 * a 128-byte probe. fs_handshake_until() touches exactly fd, the two
 * nonces, the key and key_established (verified against
 * core/modules/net/src/file_service_handshake.c), and fs_session_cleanup()
 * IS linked from that same handshake TU.
 *
 * Usage: fs_handshake_probe <host> <port> [budget_ms]
 * (budget_ms defaults to 4000 and bounds connect AND handshake together).
 * Deadline regression (no network):
 *   bash tools/scripts/fs_handshake_probe_deadline_selftest.sh
 *   bash tools/scripts/fs_handshake_probe_interrupt_selftest.sh
 *   bash tools/scripts/fs_handshake_probe_resolver_selftest.sh
 * Prints one result line on stdout on success; diagnostics on stderr. */

#include "net/file_service.h"

#include "platform/socket_compat.h"
#include "platform/time_compat.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PROBE_DEFAULT_BUDGET_MS 4000

#define PROBE_RC_OK 0
#define PROBE_RC_USAGE 2
#define PROBE_RC_UNREACHABLE 3
#define PROBE_RC_HANDSHAKE_FAILED 4

/* Milliseconds left before deadline_ms, floored at 1 and capped at INT32_MAX
 * so a poll timeout is never "block forever". 0 when the budget is spent. */
static int probe_ms_left(int64_t deadline_ms)
{
    int64_t left = deadline_ms - platform_time_monotonic_ms();
    if (left <= 0)
        return 0;
    if (left > INT32_MAX)
        return INT32_MAX;
    return (int)left;
}

/* Connect to host:port within deadline_ms. Returns the connected socket,
 * or PLATFORM_SOCKET_INVALID (diagnostic already on stderr). */
static platform_socket_t probe_connect(const char *host, const char *port,
                                       int64_t deadline_ms)
{
    /* Runtime setup or descheduling may exhaust the budget before entry.
     * Do not start a blocking resolver operation for an expired probe. */
    if (probe_ms_left(deadline_ms) <= 0) {
        fprintf(stderr,
                "fs_handshake_probe: deadline expired before resolving %s:%s\n",
                host, port);
        return PLATFORM_SOCKET_INVALID;
    }
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *addresses = NULL;
    if (getaddrinfo(host, port, &hints, &addresses) != 0 ||
        addresses == NULL) {
        fprintf(stderr, "fs_handshake_probe: cannot resolve %s:%s\n", host,
                port);
        return PLATFORM_SOCKET_INVALID;
    }

    platform_socket_t connected = PLATFORM_SOCKET_INVALID;
    for (struct addrinfo *ai = addresses; ai != NULL; ai = ai->ai_next) {
        int budget_ms = probe_ms_left(deadline_ms);
        if (budget_ms <= 0)
            break;
        platform_socket_t fd =
            platform_socket_open(ai->ai_family, ai->ai_socktype,
                                 ai->ai_protocol, true, true);
        if (fd == PLATFORM_SOCKET_INVALID)
            continue;
        int rc = platform_socket_connect(fd, ai->ai_addr,
                                         (socklen_t)ai->ai_addrlen);
        if (rc != 0 &&
            !platform_socket_error_in_progress(
                platform_socket_last_error())) {
            platform_socket_close(fd);
            continue;
        }
        if (rc != 0) {
            /* Socket setup/connect may consume the remaining budget under
             * IBD load. Never give poll the stale pre-connect timeout. */
            budget_ms = probe_ms_left(deadline_ms);
            if (budget_ms <= 0) {
                platform_socket_close(fd);
                break;
            }
            int ready;
            for (;;) {
                ready = platform_socket_wait_writable(fd, budget_ms);
                if (ready >= 0 || !platform_socket_error_interrupted(
                        platform_socket_last_error()))
                    break;
                /* A signal does not invalidate the pending connection.
                 * Retry that socket using only the original budget left. */
                budget_ms = probe_ms_left(deadline_ms);
                if (budget_ms <= 0)
                    break;
            }
            if (ready <= 0) {
                platform_socket_close(fd);
                continue;
            }
            int pending = 0;
            if (platform_socket_pending_error(fd, &pending) != 0 ||
                pending != 0) {
                platform_socket_close(fd);
                continue;
            }
        }
        connected = fd;
        break;
    }
    freeaddrinfo(addresses);

    if (connected == PLATFORM_SOCKET_INVALID)
        fprintf(stderr,
                "fs_handshake_probe: connect to %s:%s failed or timed out\n",
                host, port);
    return connected;
}

int main(int argc, char **argv)
{
    if (argc < 3 || argc > 4) {
        fprintf(stderr,
                "usage: %s <host> <port> [budget_ms=%d]\n", argv[0],
                PROBE_DEFAULT_BUDGET_MS);
        return PROBE_RC_USAGE;
    }
    const char *host = argv[1];
    const char *port = argv[2];
    long budget_ms = PROBE_DEFAULT_BUDGET_MS;
    if (argc == 4) {
        char *end = NULL;
        budget_ms = strtol(argv[3], &end, 10);
        if (end == argv[3] || *end != '\0' || budget_ms <= 0) {
            fprintf(stderr, "fs_handshake_probe: invalid budget_ms '%s'\n",
                    argv[3]);
            return PROBE_RC_USAGE;
        }
    }

    int64_t start_ms = platform_time_monotonic_ms();
    if (start_ms <= 0 || start_ms > INT64_MAX - budget_ms) {
        fprintf(stderr,
                "fs_handshake_probe: monotonic clock unavailable\n");
        return PROBE_RC_UNREACHABLE;
    }
    int64_t deadline_ms = start_ms + budget_ms;

    if (!platform_socket_runtime_init()) {
        fprintf(stderr, "fs_handshake_probe: socket runtime init failed\n");
        return PROBE_RC_UNREACHABLE;
    }

    platform_socket_t fd = probe_connect(host, port, deadline_ms);
    if (fd == PLATFORM_SOCKET_INVALID)
        return PROBE_RC_UNREACHABLE;

    struct fs_session session;
    memset(&session, 0, sizeof(session));
    session.fd = fd;
    session.start_monotonic_ms = start_ms;
    (void)platform_socket_set_no_delay(fd, true);

    uint8_t zero_root[32];
    memset(zero_root, 0, sizeof(zero_root));
    bool ok = fs_handshake_until(&session, zero_root, true, deadline_ms);
    fs_session_cleanup(&session);
    platform_socket_close(fd);

    if (!ok) {
        fprintf(stderr,
                "fs_handshake_probe: handshake_failed peer=%s:%s — the peer "
                "accepted TCP but could not complete the authenticated "
                "X25519/HKDF file-service handshake (a pre-d1db47aee7 "
                "fixture binary, a non-file-service listener, or a silent "
                "peer)\n",
                host, port);
        return PROBE_RC_HANDSHAKE_FAILED;
    }

    printf("fs_handshake_probe: handshake_ok peer=%s:%s elapsed_ms=%lld\n",
           host, port,
           (long long)(platform_time_monotonic_ms() - start_ms));
    return PROBE_RC_OK;
}
