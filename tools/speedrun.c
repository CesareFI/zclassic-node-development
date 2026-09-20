/* Copyright 2026 Rhett Creighton - Apache License 2.0
 * Z23 File-Service Startup Timing
 *
 * Measures the app_init startup attempt with a file-service peer.
 * Connects to a RUNNING power node's file service over TCP.
 * No source node shutdown required.
 * app_init may return while catch-up and validation continue in background;
 * this tool does not measure time to tip or sovereign validation completion.
 *
 * Build: make speedrun
 * Usage: build/bin/speedrun [peer_address]
 *   Default peer: 127.0.0.1 (localhost power node)
 *
 * Exit: 0 means startup completed, 1 means startup failed. Neither proves
 * completed synchronization. Report the startup duration even on failure.
 */

#include "platform/time_compat.h"
#include "config/boot.h"
#include "chain/chainparams.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>
#include <signal.h>

/* Required by process_block.c */
volatile sig_atomic_t g_shutdown_requested = 0;

static inline int64_t now_ms(void)
{
    struct timespec ts;
    platform_time_monotonic_timespec(&ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(int argc, char *argv[])
{
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    const char *peer = "127.0.0.1";
    if (argc >= 2)
        peer = argv[1];

    /* PID reuse must not turn a fresh-start measurement into a resume.
     * Reserve an empty, private directory before starting the clock. */
    char dst_base[256] = "/tmp/zcl23-speedrun-XXXXXX";
    if (!mkdtemp(dst_base)) {
        perror("speedrun: create fresh startup datadir");
        return 1;
    }

    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║     Z23 File-Service Startup Timing                   ║\n");
    printf("╚══════════════════════════════════════════════════════╝\n\n");
    printf("Peer:    %s:18034\n", peer);
    printf("Target:  %s\n\n", dst_base);

    int64_t t_startup = now_ms();

    /* Boot with -fileservice= pointing to the power node.
     * The boot sequence will:
     *   1. Connect to file service, download all data
     *   2. Load block index from flat file
     *   3. Import consensus snapshot or replay
     *   4. Start background UTXO replay if needed */
    struct app_context ctx;
    app_context_defaults(&ctx);
    ctx.datadir = dst_base;
    ctx.file_service_peer = peer;
    ctx.listen = false;
    ctx.p2p_port = 18044;
    ctx.rpc_port = 18245;
    ctx.tor = false;

    bool ok = app_init(&ctx);

    int64_t startup_ms = now_ms() - t_startup;

    printf("\n");
    printf("╔══════════════════════════════════════════════════════╗\n");
    printf("║  STARTUP RESULT                                      ║\n");
    printf("╠══════════════════════════════════════════════════════╣\n");
    printf("║  Startup attempt:     %6lldms  (%4.1fs)            ║\n",
           (long long)startup_ms, (double)startup_ms / 1000.0);
    printf("║  Startup status: %s                            ║\n",
           ok ? "COMPLETE" : "FAILED  ");
    printf("╚══════════════════════════════════════════════════════╝\n");
    printf("Time to tip: NOT MEASURED\n");
    printf("Sovereign validation: NOT MEASURED\n");

    printf("\nTemp data at: %s\n", dst_base);
    printf("Clean up with: rm -rf %s\n", dst_base);

    return ok ? 0 : 1;
}
