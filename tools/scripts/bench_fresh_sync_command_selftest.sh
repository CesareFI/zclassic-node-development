#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the benchmark's real command reader without a node or network.
# Usage: bash tools/scripts/bench_fresh_sync_command_selftest.sh [--analyze] [source.c]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
analyze=false
if [ "${1:-}" = --analyze ]; then analyze=true; shift; fi
SOURCE="${1:-$ROOT/tools/bench_fresh_sync.c}"
TMP="$(mktemp -d /tmp/zcl-bench-command.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <sys/wait.h>

#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
EOF
awk '/^static int run_cmd\(/ { copy = 1 }
     /^\/\* RPC call/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
awk '/^static bool json_get_str\(/ { copy = 1 }
     /^static long json_get_int/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'EOF'
int main(int argc, char **argv)
{
    if (argc == 4 && strcmp(argv[1], "--emit") == 0) {
        long count = strtol(argv[2], NULL, 10);
        for (long i = 0; i < count; i++)
            if (putchar('x') == EOF) return 8;
        if (fflush(stdout) != 0) return 8;
        return atoi(argv[3]);
    }
    CHECK(argc == 1);
    char cmd[512], buf[32];
    /* Bigger than the pipe: truncated output must not become evidence. */
    CHECK(snprintf(cmd, sizeof(cmd), "'%s' --emit 1048576 0", argv[0]) > 0);
    memset(buf, 'z', sizeof(buf));
    CHECK(run_cmd(cmd, buf, sizeof(buf)) == 0);
    CHECK(buf[0] == '\0'); /* Never accept an incomplete RPC response. */
    puts("PASS: 1 MiB response rejected");
    const int sizes[] = {0, 1, 30, 31, 32};
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        CHECK(snprintf(cmd, sizeof(cmd), "'%s' --emit %d 0", argv[0], sizes[i]) > 0);
        memset(buf, 'z', sizeof(buf));
        int expected = sizes[i] < (int)sizeof(buf) ? sizes[i] : 0;
        CHECK(run_cmd(cmd, buf, sizeof(buf)) == expected);
        CHECK(buf[expected] == '\0');
        for (int j = 0; j < expected; j++) CHECK(buf[j] == 'x');
    }
    CHECK(snprintf(cmd, sizeof(cmd), "'%s' --emit 10 7", argv[0]) > 0);
    CHECK(run_cmd(cmd, buf, sizeof(buf)) == 0);
    CHECK(buf[0] == '\0');
    CHECK(run_cmd("kill -TERM $$", buf, sizeof(buf)) == 0);
    CHECK(buf[0] == '\0');
    char state[16] = "unknown";
    CHECK(run_cmd("printf '{\"state\":\"at_tip\"}'; exit 7", buf, sizeof(buf)) == 0);
    CHECK(!json_get_str(buf, "state", state, sizeof(state)));
    CHECK(strcmp(state, "unknown") == 0);
    CHECK(run_cmd("printf x", buf, 1) == 0 && buf[0] == '\0');
    CHECK(run_cmd("true", buf, 1) == 0 && buf[0] == '\0');
    puts("PASS: empty, short, exact-fit, overflow, exit failure, signal, false tip, one-byte buffer");
    return 0;
}
EOF
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror -D_POSIX_C_SOURCE=200809L \
    "$TMP/test.c" -o "$TMP/test"
# Optional compiler diagnostics on the exact extracted production helpers.
if "$analyze"; then
    "${CC:-cc}" -std=c23 -Wall -Wextra -Werror -fanalyzer \
        -D_POSIX_C_SOURCE=200809L -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
# Bound the regression independently of the command reader.
timeout 5 "$TMP/test"
