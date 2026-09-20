#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Curl status fixture with the actual observers; no node or network access.
# Usage: bash tools/scripts/bench_fresh_sync_http_error_selftest.sh [--baseline] [--analyze] [source.c]
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
scratch=$(mktemp -d /tmp/zcl-http-error.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
export ZCL_HTTP_FIXTURE_STATUS=200
cat > "$scratch/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
fail=0
counter=0
for arg in "$@"; do
    case $arg in
        --fail) fail=1 ;;
        '%{size_download}') counter=1 ;;
        https://127.0.0.1:8447/explorer*) ;;
        http://*|https://*) echo 'unexpected fixture URL' >&2; exit 1 ;;
    esac
done
if (( fail && ZCL_HTTP_FIXTURE_STATUS >= 400 )); then
    (( ! counter )) || printf 0
    exit 22
fi
if (( counter )); then printf 13; else printf 'Latest Blocks'; fi
SH
chmod +x "$scratch/curl"
cat > "$scratch/test.c" <<'C'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#define HTTPSPORT 8447
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
C
# Extract the actual observers, refusing incomplete extraction.
awk '/^static (int run_cmd|void phase_log_normalize|bool explorer_responding|int explorer_page_size)\(/ { copy = 1; count++ }
     copy { print }
     /^}/ { copy = 0 }
     END { if (count != 4) exit 1 }' "$source_file" >> "$scratch/test.c"
cat >> "$scratch/test.c" <<'C'
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    const int statuses[] = {200, 404, 429, 500, 503};
    unsigned false_ready = 0;
    for (size_t i = 0; i < sizeof(statuses) / sizeof(statuses[0]); i++) {
        char status_text[16];
        CHECK(snprintf(status_text, sizeof(status_text), "%d", statuses[i]) > 0);
        CHECK(setenv("ZCL_HTTP_FIXTURE_STATUS", status_text, 1) == 0);
        bool ready = explorer_responding();
        int size = explorer_page_size("/explorer");
        printf("HTTP %d: ready=%d size=%d\n", statuses[i], ready, size);
        bool accepted = statuses[i] == 200 || baseline;
        CHECK(ready == accepted && size == (accepted ? 13 : 0));
        if (statuses[i] >= 400 && ready) false_ready++;
    }
    printf("false readiness observations=%u/4\n", false_ready);
    puts("bench-fresh-sync-http-error-selftest: PASS");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -D_POSIX_C_SOURCE=200809L)
"${CC:-cc}" "${flags[@]}" -O2 "$scratch/test.c" -o "$scratch/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$scratch/test.c" -o "$scratch/analyzed.o"
fi
PATH="$scratch:$PATH" timeout 20 "$scratch/test" "$baseline"
