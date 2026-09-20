#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Run the benchmark output setup and banner with isolated fixture paths.
# A handshake holds it alive while the parent observes stdout.
# Usage: bash tools/scripts/bench_fresh_sync_output_selftest.sh [--baseline] [--analyze] [source.c]
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
scratch=$(mktemp -d "${TMPDIR:-/tmp}/zcl-bench-output.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/test.c" <<'C'
#include "platform/time_compat.h"
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static int ready_fd, release_fd;
static double now_sec(void)
{
    return (double)clock_now_monotonic_ns() / 1e9;
}
static void fixture_hold(void)
{
    char token;
    CHECK(write(ready_fd, "r", 1) == 1);
    CHECK(read(release_fd, &token, 1) == 1);
}
C
# Compile the actual output configuration helper, then the entry-point banner.
# Omit datadir/certificate setup and all node/network code. Require every
# boundary so an empty extraction cannot claim a passing observation.
awk '
    /^static bool benchmark_progress_output\(/ { helper = 1; helpers++ }
    /^static void benchmark_validation\(/ { helper = 0; helper_ends++ }
    /^int main\(void\)/ {
        entry++
        print "static int benchmark_main(void)"
        print "{"
        print "    if (!benchmark_progress_output()) return 1;"
        print "    const char *binary = \"fixture\", *datadir = \"/unused-fixture\";"
        print "    enum { PORT = 8047, RPCPORT = 18247, HTTPSPORT = 8447 };"
    }
    /^    printf\("\\n"\);/ && !banner_done { banner = 1 }
    /^    double t0 = now_sec\(\);/ { banner = 0; banner_done = 1; finish++ }
    helper || banner { print }
    END { if (helpers != 1 || helper_ends != 1 || entry != 1 || finish != 1) exit 1 }
' "$source_file" >> "$scratch/test.c"
cat >> "$scratch/test.c" <<'C'
    fixture_hold();
    return 0;
}
static void observe(bool baseline, bool regular_file)
{
    int output[2], ready[2], release[2];
    CHECK(pipe(output) == 0 && pipe(ready) == 0 && pipe(release) == 0);
    FILE *file = regular_file ? tmpfile() : NULL;
    CHECK(!regular_file || file != NULL);
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        /* Bound fixture failures even if a handshake never arrives. */
        alarm(5);
        CHECK(close(output[0]) == 0 && close(ready[0]) == 0 && close(release[1]) == 0);
        int stdout_fd = dup2(regular_file ? fileno(file) : output[1], STDOUT_FILENO);
        CHECK(stdout_fd >= 0);
        CHECK(close(output[1]) == 0);
        ready_fd = ready[1];
        release_fd = release[0];
        int rc = benchmark_main();
        CHECK(rc == 0);
        CHECK(fflush(stdout) == 0);
        CHECK(close(stdout_fd) == 0);
        exit(0);
    }
    CHECK(close(output[1]) == 0 && close(ready[1]) == 0 && close(release[0]) == 0);
    struct pollfd handshake = { .fd = ready[0], .events = POLLIN };
    CHECK(poll(&handshake, 1, 3000) == 1);
    char token;
    CHECK(read(ready[0], &token, 1) == 1 && token == 'r');
    int status;
    CHECK(waitpid(child, &status, WNOHANG) == 0);
    size_t visible = 0;
    char before[2048] = {0};
    double start = now_sec();
    if (regular_file) {
        struct stat st;
        CHECK(fstat(fileno(file), &st) == 0 && st.st_size >= 0);
        visible = (size_t)st.st_size;
    } else {
        struct pollfd observation = { .fd = output[0], .events = POLLIN };
        int rc = poll(&observation, 1, 500);
        CHECK(rc >= 0);
        if (rc == 1) {
            ssize_t n = read(output[0], before, sizeof(before) - 1);
            CHECK(n > 0);
            visible = (size_t)n;
        }
    }
    double wait_ms = (now_sec() - start) * 1000;
    CHECK(baseline ? visible == 0 : visible > 0);
    CHECK(write(release[1], "x", 1) == 1);
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    char all[2048] = {0};
    size_t count = 0;
    if (regular_file) {
        rewind(file);
        count = fread(all, 1, sizeof(all) - 1, file);
        CHECK(!ferror(file));
        CHECK(fclose(file) == 0);
    } else {
        memcpy(all, before, visible);
        count = visible;
        ssize_t n;
        while ((n = read(output[0], all + count, sizeof(all) - 1 - count)) > 0)
            count += (size_t)n;
        CHECK(n == 0);
    }
    CHECK(count > 0 && count < sizeof(all) - 1);
    CHECK(strstr(all, "Z23 Cold-Start Benchmark") != NULL);
    CHECK(strstr(all, "Ports:   P2P=8047 RPC=18247 HTTPS=8447\n") != NULL);
    CHECK(baseline || visible == count);
    CHECK(close(output[0]) == 0 && close(ready[0]) == 0 && close(release[1]) == 0);
    /* stderr avoids leaving parent stdout bytes for the next fork to copy. */
    fprintf(stderr, "destination=%s visible_before_exit=%zu total=%zu observation_wait_ms=%.3f\n",
            regular_file ? "file" : "pipe", visible, count, wait_ms);
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    observe(argv[1][0] == '1', false);
    observe(argv[1][0] == '1', true);
    puts("bench-fresh-sync-output-selftest: PASS");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -D_DEFAULT_SOURCE
    -I"$root/platform/modules/platform/include"
    -I"$root/platform/modules/base/include"
    -I"$root/platform/modules/util/include")
"${CC:-cc}" "${flags[@]}" -O2 "$scratch/test.c" \
    "$root/platform/modules/platform/src/clock.c" \
    "$root/platform/modules/base/src/log_level.c" -o "$scratch/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$scratch/test.c" -o "$scratch/analyzed.o"
fi
"$scratch/test" "$baseline"
