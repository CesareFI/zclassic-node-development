#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Actual ontology lookup versus the linear oracle; no node or network.
# Usage: bash tools/scripts/telemetry_lookup_selftest.sh [--baseline] [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/platform/modules/util/src/telemetry_ontology.c}
fixture=$(mktemp -d /tmp/z23-telemetry-lookup.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cp "$subject" "$fixture/subject.c"
awk '/^const struct telemetry_field \*telemetry_field_lookup/ {copy=1}
     copy {print; if ($0 == "}") exit}' "$subject" > "$fixture/lookup.c"
cat > "$fixture/test.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static size_t comparisons;
static bool counting;
static int counted_strcmp(const char *a, const char *b)
{
    if (counting) comparisons++;
    return strcmp(a, b);
}
#define strcmp counted_strcmp
#include "subject.c"
#undef strcmp
/* Compile the same function against interleaved groups whose equal names
 * deliberately occupy different storage. No pooling assumption is needed
 * for correctness, and a duplicate key must still return the first row. */
static char sync_a[] = "sync", sync_b[] = "sync";
static const struct telemetry_field fixture_fields[] = {
    {.subsystem = sync_a, .path = "one"},
    {.subsystem = sync_b, .path = "two"},
    {.subsystem = sync_b, .path = "two_again"},
    {.subsystem = "other", .path = "one"},
    {.subsystem = sync_a, .path = "three"},
    {.subsystem = sync_b, .path = "one"},
};
#define g_fields fixture_fields
#define telemetry_field_lookup fixture_lookup
#undef FIELD_COUNT
#define FIELD_COUNT (sizeof(fixture_fields) / sizeof(fixture_fields[0]))
#define strcmp counted_strcmp
#include "lookup.c"
#undef strcmp
#undef g_fields
#undef telemetry_field_lookup
#undef FIELD_COUNT
#define FIELD_COUNT (sizeof(g_fields) / sizeof(g_fields[0]))
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static const struct telemetry_field *linear(const char *sub, const char *path)
{
    if (!sub || !path) return NULL;
    for (size_t i = 0; i < FIELD_COUNT; i++)
        if (strcmp(g_fields[i].subsystem, sub) == 0 &&
            strcmp(g_fields[i].path, path) == 0) return &g_fields[i];
    return NULL;
}
static void check(const char *sub, const char *path)
{
    CHECK(telemetry_field_lookup(sub, path) == linear(sub, path));
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    CHECK(sync_a != &sync_b[0]);
    CHECK(fixture_lookup("sync", "one") == &fixture_fields[0]);
    CHECK(fixture_lookup("sync", "two") == &fixture_fields[1]);
    CHECK(fixture_lookup("sync", "two_again") == &fixture_fields[2]);
    CHECK(fixture_lookup("other", "one") == &fixture_fields[3]);
    CHECK(fixture_lookup("sync", "three") == &fixture_fields[4]);
    counting = true;
    CHECK(fixture_lookup("sync", "missing") == NULL);
    printf("fixture_string_comparisons=%zu\n", comparisons);
    /* Five subsystem runs and five paths. This work bound uses explicit
     * shared storage, so it does not depend on compiler literal pooling. */
    if (atoi(argv[1]) == 0) CHECK(comparisons == 10);
    check(NULL, NULL); check(NULL, "x"); check("sync", NULL);
    check("", ""); check("missing-subsystem", "missing-path");
    size_t sync_fields = 0;
    counting = true;
    for (size_t i = 0; i < FIELD_COUNT; i++) {
        /* Caller strings need not share the table's literal storage. */
        char sub[256], path[256];
        CHECK(strlen(g_fields[i].subsystem) < sizeof sub);
        CHECK(strlen(g_fields[i].path) < sizeof path);
        strcpy(sub, g_fields[i].subsystem);
        strcpy(path, g_fields[i].path);
        check(sub, path);
        check(sub, "missing-path");
        check("missing-subsystem", path);
        if (strcmp(sub, "sync") == 0) sync_fields++;
    }
    CHECK(sync_fields > 0);
    comparisons = 0;
    for (size_t i = 0; i < FIELD_COUNT; i++)
        if (strcmp(g_fields[i].subsystem, "sync") == 0)
            check("sync", g_fields[i].path);
    printf("sync_fields=%zu lookup_string_comparisons=%zu\n", sync_fields, comparisons);
    counting = false;
    struct timespec start, end;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
    size_t hits = 0;
    for (size_t round = 0; round < 10000; round++)
        for (size_t i = 0; i < FIELD_COUNT; i++)
            if (strcmp(g_fields[i].subsystem, "sync") == 0)
                hits += telemetry_field_lookup("sync", g_fields[i].path) != NULL;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
    CHECK(hits == 10000 * sync_fields);
    printf("lookups=%zu wall_ms=%.3f\n", hits,
           (end.tv_sec - start.tv_sec) * 1000.0 + (end.tv_nsec - start.tv_nsec) / 1e6);
    puts("PASS: all fields, caller copies, missing keys and NULL inputs match linear oracle");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -O2 -Wall -Wextra -Werror
    -ffunction-sections -fdata-sections)
while IFS= read -r dir; do flags+=(-I"$root/$dir"); done < <(
    git -C "$root" ls-files '*include/*.h' | sed 's@/include/.*@/include@' | sort -u
)
if [[ ${SANITIZE:-0} == 1 ]]; then
    flags+=(-fsanitize=address,undefined -fno-omit-frame-pointer)
fi
link_flags=(-Wl,--gc-sections)
if [[ $(uname -s) == Darwin ]]; then link_flags=(-Wl,-dead_strip); fi
"${CC:-cc}" "${flags[@]}" "$fixture/test.c" "${link_flags[@]}" -o "$fixture/test"
if [[ ${ANALYZE:-0} == 1 ]]; then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$subject" -o "$fixture/analyzed.o"
fi
"$fixture/test" "$baseline"
