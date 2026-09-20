#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise the production IBD child observation without a node or real signals.
# Usage: bash tools/scripts/bench_fresh_sync_poll_interrupt_selftest.sh [--baseline] [--analyze] [source.c]
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
fixture=$(mktemp -d /tmp/zcl-poll-interrupt.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
#define WNOHANG 1
static int g_child, remaining, waits, diagnostics, mode;
static pid_t waitpid(pid_t child, int *status, int flags)
{
    CHECK(child == 42 && flags == WNOHANG && ++waits <= 4);
    if (remaining > 0) {
        remaining--;
        errno = EINTR;
        return -1;
    }
    if (mode == 1) { *status = 1 << 8; return child; }
    if (mode == 2) { errno = ECHILD; return -1; }
    return 0; /* Leave errno stale after an interruption, like real waitpid. */
}
static int fixture_system(const char *cmd)
{
    CHECK(strcmp(cmd, "tail -20 'fixture.log'") == 0);
    diagnostics++;
    return 0;
}
#define system fixture_system
static int observe(void)
{
    const char *logfile = "fixture.log";
C
awk '/^        \/\* Check child alive \*\// { copy = 1 }
     /^        \/\* Get sync state \*\// { copy = 0 }
     copy { print }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
    return 0;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    int baseline = strcmp(argv[1], "1") == 0, preserved = 0;
    for (mode = 0; mode < 3; mode++) {
        for (int signals = 0; signals <= 3; signals++) {
            g_child = 42;
            remaining = signals;
            waits = diagnostics = 0;
            errno = 0;
            int rc = observe();
            int failed = mode != 0 || (baseline && signals > 0);
            printf("mode=%d interruptions=%d rc=%d wait_calls=%d\n",
                   mode, signals, rc, waits);
            CHECK(rc == failed);
            CHECK(waits == (baseline ? 1 : signals + 1));
            CHECK(diagnostics == failed);
            CHECK(g_child == (failed ? 0 : 42));
            if (mode == 0 && rc == 0) preserved++;
        }
    }
    printf("live_measurements_preserved=%d/4\n", preserved);
    puts("PASS: interrupted IBD observations; exited and missing children still refuse");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 5 "$fixture/test" "$baseline"
