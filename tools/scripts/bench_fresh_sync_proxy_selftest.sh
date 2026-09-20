#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Check production observer routing with real curl and an ambient proxy.
# Only closed loopback ports are used; no node or listener participates.
# Usage: bash tools/scripts/bench_fresh_sync_proxy_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=false
analyze=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline) baseline=true; shift ;;
        --analyze) analyze=true; shift ;;
        *) break ;;
    esac
done
SOURCE=${1:-$ROOT/tools/bench_fresh_sync.c}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/zcl-bench-proxy.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
export SELFTEST_PROXY_CURL SELFTEST_PROXY_FIXTURE="$TMP"
SELFTEST_PROXY_CURL=$(command -v curl)
mkdir "$TMP/bin" "$TMP/config"
export CURL_HOME="$TMP/config"
printf '{"state":"at_tip"}' > "$TMP/rpc"
printf 'Latest Blocks' > "$TMP/page"
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=()
for arg in "$@"; do
    case "$arg" in
        http://127.0.0.1:18247/)
            arg=http://127.0.0.1:0/
            if [[ ${SELFTEST_PROXY_SUCCESS:-0} == 1 ]]; then arg="file://$SELFTEST_PROXY_FIXTURE/rpc"; fi ;;
        https://127.0.0.1:8447/explorer*)
            arg=https://127.0.0.1:0/
            if [[ ${SELFTEST_PROXY_SUCCESS:-0} == 1 ]]; then arg="file://$SELFTEST_PROXY_FIXTURE/page"; fi ;;
        http://*|https://*) echo 'unexpected observer destination' >&2; exit 1 ;;
    esac
    args+=("$arg")
done
# Preserve production options, including any proxy bypass. Port zero has no
# listener. Bound even old source versions that had no observer deadline.
exec "$SELFTEST_PROXY_CURL" "${args[@]}" --verbose --max-time 0.1 \
    2> "$SELFTEST_PROXY_FIXTURE/trace.$$"
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
C
awk '/^static (int run_cmd|bool rpc_call|void phase_log_normalize|bool explorer_responding|int explorer_page_size)\(/ { copy = 1 }
     copy { print }
     /^}/ { copy = 0 }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
int main(int argc, char **argv)
{
    char buf[256] = "";
    bool rpc = rpc_call("fixture:fixture", "syncstate", buf, sizeof(buf));
    bool page = explorer_responding();
    int size = explorer_page_size("/explorer");
    if (argc == 2 && strcmp(argv[1], "success") == 0) {
        if (rpc && page && size == 13 && strcmp(buf, "{\"state\":\"at_tip\"}") == 0)
            return 0;
        fprintf(stderr, "FAIL: successful observer evidence changed\n");
        return 1;
    }
    if (rpc || page || size != 0) {
        fprintf(stderr, "FAIL: closed endpoints produced readiness evidence\n");
        return 1;
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
# A SOCKS proxy on port zero is guaranteed closed. All proxy variable
# spellings are explicit so the invoking environment cannot affect the test.
export http_proxy=socks5h://127.0.0.1:0 https_proxy=socks5h://127.0.0.1:0
export all_proxy=socks5h://127.0.0.1:0 ALL_PROXY=socks5h://127.0.0.1:0
export HTTP_PROXY=socks5h://127.0.0.1:0 HTTPS_PROXY=socks5h://127.0.0.1:0
export no_proxy= NO_PROXY=
export SELFTEST_PROXY_SUCCESS=0
timeout 5 "$TMP/test"
traces=("$TMP"/trace.*)
[[ ${#traces[@]} == 3 ]] || { echo 'FAIL: expected three HTTP observations' >&2; exit 1; }
proxied=0
for trace in "${traces[@]}"; do
    if grep -q 'Uses proxy env variable' "$trace"; then proxied=$((proxied + 1)); fi
    grep -Eq 'port 0|127\.0\.0\.1:0' "$trace" || {
        echo 'FAIL: curl did not attempt the closed loopback fixture' >&2; exit 1;
    }
done
printf 'Three observers: %d inherited proxy routes\n' "$proxied"
expected=0
if "$baseline"; then expected=3; fi
[[ $proxied == "$expected" ]] || { echo 'FAIL: unexpected proxy routing' >&2; exit 1; }
SELFTEST_PROXY_SUCCESS=1 timeout 5 "$TMP/test" success
echo 'PASS: observer routing and missing-evidence contract'
