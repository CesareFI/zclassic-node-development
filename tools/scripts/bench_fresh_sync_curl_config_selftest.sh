#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise real curl with the production observer arguments and local files.
# No node, network listener, credentials or production datadir participates.
# Usage: bash tools/scripts/bench_fresh_sync_curl_config_selftest.sh [--bench] [--analyze] [source.c]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
bench=false
analyze=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bench) bench=true; shift ;;
        --analyze) analyze=true; shift ;;
        *) break ;;
    esac
done
SOURCE=${1:-$ROOT/tools/bench_fresh_sync.c}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/zcl-bench-curl-config.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export ZCL_FIXTURE_CURL
ZCL_FIXTURE_CURL=$(command -v curl)
export ZCL_CURL_FIXTURE_DIR="$TMP"
mkdir "$TMP/bin" "$TMP/config"
export CURL_HOME="$TMP/config"
printf '{"state":"at_tip"}' > "$TMP/rpc"
printf 'Latest Blocks' > "$TMP/page"

# Preserve every production curl option and its order. Substitute only the
# fixed loopback destinations with file:// fixtures; reject other URLs.
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=()
for arg in "$@"; do
    case "$arg" in
        http://127.0.0.1:18247/) arg="file://$ZCL_CURL_FIXTURE_DIR/rpc" ;;
        https://127.0.0.1:8447/explorer*) arg="file://$ZCL_CURL_FIXTURE_DIR/page" ;;
        http://*|https://*) echo 'unexpected observer URL' >&2; exit 1 ;;
    esac
    args+=("$arg")
done
exec "$ZCL_FIXTURE_CURL" "${args[@]}"
SH
chmod +x "$TMP/bin/curl"
cat > "$TMP/test.c" <<'C'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#define RPCPORT 18247
#define HTTPSPORT 8447
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
C
awk '/^static (int run_cmd|bool rpc_call|void phase_log_normalize|bool explorer_responding|int explorer_page_size)\(/ { copy = 1 }
     copy { print }
     /^}/ { copy = 0 }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool failure = strcmp(argv[1], "failure") == 0;
    struct timespec begin, end;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &begin) == 0);
    char buf[256] = "";
    bool rpc = rpc_call("fixture:fixture", "syncstate", buf, sizeof(buf));
    bool page = explorer_responding();
    int size = explorer_page_size("/explorer");
    CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
    double elapsed = (double)(end.tv_sec - begin.tv_sec) +
                     (double)(end.tv_nsec - begin.tv_nsec) / 1e9;
    printf("%s: three observers %.6f s rpc=%d page=%d bytes=%d\n",
           argv[1], elapsed, rpc, page, size);
    if (failure) {
        CHECK(!rpc && !page && size == 0 && buf[0] == '\0');
    } else {
        CHECK(rpc && page && size == 13);
        CHECK(strcmp(buf, "{\"state\":\"at_tip\"}") == 0);
    }
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -D_POSIX_C_SOURCE=200809L)
"${CC:-cc}" "${flags[@]}" -O2 "$TMP/test.c" -o "$TMP/test"
if "$analyze"; then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
export PATH="$TMP/bin:$PATH"
timeout 15 "$TMP/test" clean
if "$bench"; then
    # Retry delay lies outside --max-time's per-transfer limit. Measure missing
    # local files so no network or server timing affects the comparison.
    rm "$TMP/rpc" "$TMP/page"
    printf 'retry = 1\nretry-all-errors\nretry-delay = 1\n' > "$CURL_HOME/.curlrc"
    for iteration in 1 2 3; do
        timeout 15 "$TMP/test" failure
    done
else
    # A default config can both redirect evidence and append unrelated bodies.
    # Both must be ignored, including when the requested transfer fails.
    printf 'output = "%s/redirected"\n' "$TMP" > "$CURL_HOME/.curlrc"
    timeout 15 "$TMP/test" redirected
    [[ ! -e "$TMP/redirected" ]] || { echo 'FAIL: curl loaded output configuration' >&2; exit 1; }
    printf 'url = "file://%s/page"\n' "$TMP" > "$CURL_HOME/.curlrc"
    timeout 15 "$TMP/test" extra-url
    rm "$TMP/rpc"
    mv "$TMP/page" "$TMP/extra"
    printf 'url = "file://%s/extra"\n' "$TMP" > "$CURL_HOME/.curlrc"
    timeout 15 "$TMP/test" failure
    printf 'PASS: ambient redirects and extra URLs cannot change observer evidence\n'
fi
