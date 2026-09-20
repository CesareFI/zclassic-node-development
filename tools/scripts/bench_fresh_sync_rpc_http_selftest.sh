#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Measure rejected HTTP RPC samples using the real observer and transition code.
# Usage: bash tools/scripts/bench_fresh_sync_rpc_http_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0 analyze=0
while [[ ${1:-} == --* ]]; do
    case $1 in
        --baseline) baseline=1 ;;
        --analyze) analyze=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
source_file=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/zcl-rpc-http.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
export ZCL_RPC_HTTP_CALLS="$fixture/calls"
cat > "$fixture/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
fail=0 method=''
for arg in "$@"; do
    case $arg in
        --fail) fail=1 ;;
        *'"method":"syncstate"'*) method=state ;;
        *'"method":"getblockcount"'*) method=height ;;
        http://127.0.0.1:18247/) ;;
        http://*|https://*) exit 2 ;;
    esac
done
[[ -n $method ]]
printf '%s\n' "$method" >> "$ZCL_RPC_HTTP_CALLS"
if (( fail && ZCL_RPC_HTTP_STATUS >= 400 )); then exit 22; fi
# Error documents can contain state-looking fields. HTTP success is required
# before these bytes may establish a timed observation, whatever their shape.
if [[ $method == state ]]; then
    printf '{"state":"at_tip"}'
else
    printf '{"result":123}'
fi
SH
chmod +x "$fixture/curl"
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
#define RPCPORT 18247
#define TIMEOUT 1800
static double now_sec(void) { return 1; }
C
awk '/^static (int run_cmd|bool rpc_call|bool json_get_str|long json_get_int)\(/ { copy = 1; count++ }
     copy { print }
     /^}/ { copy = 0 }
     END { if (count != 4) exit 1 }' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
static long observe(char *last_state)
{
    const char *cookie = "fixture:fixture";
    char rpc_buf[4096];
    double t0 = 0;
C
awk '/^        \/\* Get sync state \*\// { copy = 1; starts++ }
     copy { print }
     copy && /strcpy\(last_state, state\)/ { getline; print; ends++; exit }
     END { if (starts != 1 || ends != 1) exit 1 }' \
    "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
    return height;
}
static int count_calls(void)
{
    FILE *f = fopen(getenv("ZCL_RPC_HTTP_CALLS"), "r");
    CHECK(f != NULL);
    int count = 0, c;
    while ((c = fgetc(f)) != EOF) if (c == '\n') count++;
    CHECK(!ferror(f) && fclose(f) == 0);
    return count;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    const int statuses[] = {200, 400, 401, 403, 404, 429, 500, 503};
    int false_tip = 0, unnecessary_height = 0;
    for (size_t i = 0; i < sizeof(statuses) / sizeof(statuses[0]); i++) {
        char text[16], last_state[64] = "syncing";
        CHECK(snprintf(text, sizeof(text), "%d", statuses[i]) > 0);
        CHECK(setenv("ZCL_RPC_HTTP_STATUS", text, 1) == 0);
        FILE *f = fopen(getenv("ZCL_RPC_HTTP_CALLS"), "w");
        CHECK(f != NULL && fclose(f) == 0);
        long height = observe(last_state);
        int calls = count_calls();
        bool accepted = statuses[i] == 200 || baseline;
        printf("HTTP %d: state=%s height=%ld RPC_calls=%d\n",
               statuses[i], last_state, height, calls);
        CHECK(strcmp(last_state, accepted ? "at_tip" : "unknown") == 0);
        CHECK(height == (accepted ? 123 : -1));
        CHECK(calls == (accepted ? 2 : 1));
        if (statuses[i] >= 400) {
            false_tip += strcmp(last_state, "at_tip") == 0;
            unnecessary_height += calls - 1;
        }
        /* Repeated failed samples stay unavailable; a later HTTP success
         * still records the real transition and its height. */
        CHECK(observe(last_state) == -1);
        CHECK(count_calls() == calls + 1);
        CHECK(setenv("ZCL_RPC_HTTP_STATUS", "200", 1) == 0);
        CHECK(observe(last_state) == (accepted ? -1 : 123));
        CHECK(strcmp(last_state, "at_tip") == 0);
        CHECK(count_calls() == calls + (accepted ? 2 : 3));
    }
    printf("false tip observations=%d/7 unnecessary height RPCs=%d/7\n",
           false_tip, unnecessary_height);
    puts("PASS: HTTP errors, repeated failures, successful observation and recovery");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
PATH="$fixture:$PATH" timeout 20 "$fixture/test" "$baseline"
