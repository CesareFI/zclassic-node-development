#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Exercise the production final report without a node, network or datadir.
# Usage: bash tools/scripts/bench_fresh_sync_report_demand_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
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
SOURCE=${1:-$ROOT/tools/bench_fresh_sync.c}
TMP=$(mktemp -d /tmp/zcl-report-demand.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define TIMEOUT 1800
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(1); \
} } while (0)
static unsigned pages, validation_calls, http_budget;
static bool validation_ok;
static int explorer_page_size(const char *path)
{
    static const char *const paths[] = {
        "/explorer", "/explorer/factoids", "/explorer/hodl", "/explorer/stats"
    };
    CHECK(pages < 4 && strcmp(path, paths[pages]) == 0);
    pages++;
    http_budget += 2; /* Each production curl has --max-time 2. */
    return 0; /* A stalled or empty page never proves successful IBD. */
}
static bool rpc_call(const char *cookie, const char *method, char *buf, int size)
{
    CHECK(strcmp(cookie, "fixture") == 0);
    CHECK(strcmp(method, "validationstatus") == 0);
    validation_calls++;
    CHECK(snprintf(buf, (size_t)size,
          "{\"state\":\"validating\",\"verified_height\":123,\"proofs_verified\":456}") < size);
    return validation_ok;
}
C
awk '/^static bool json_get_str\(/ { copy = 1 }
     /^enum log_phase/ { copy = 0 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
static int report(double t_explorer, double t_done)
{
    const char *cookie = "fixture", *datadir = "fixture", *logfile = "fixture";
    char rpc_buf[4096];
C
awk '/^    \/\* Test explorer pages \*\// { copy = 1 }
     copy { print }' "$SOURCE" >> "$TMP/test.c"
cat >> "$TMP/test.c" <<'C'
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    for (int scenario = 0; scenario < 6; scenario++) {
        bool ready = scenario % 3 != 0;
        bool complete = scenario % 3 == 2;
        validation_ok = scenario < 3;
        pages = validation_calls = http_budget = 0;
        int rc = report(ready ? 10 : 0, complete ? 20 : 0);
        CHECK(rc == (complete ? 0 : 1));
        CHECK(validation_calls == 1);
        printf("scenario=%d ready=%d complete=%d validation_ok=%d page_requests=%u max_http_wait_seconds=%u\n",
               scenario, ready, complete, validation_ok, pages, http_budget);
        CHECK(pages == ((baseline ? ready : complete) ? 4u : 0u));
    }
    puts("PASS: report demand, page order, validation observation and exit status");
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$TMP/test.c" -o "$TMP/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$TMP/test.c" -o "$TMP/analyzed.o"
fi
timeout 10 "$TMP/test" "$baseline"
