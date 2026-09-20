#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Node-free regression/benchmark of the real telemetry renderer and evaluator.
# Usage: bash tools/scripts/telemetry_evaluation_copy_selftest.sh [--baseline] [source.c]
# OUTPUT records deterministic rendered documents for before/after comparison.
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/platform/modules/util/src/telemetry_render.c}
fixture=$(mktemp -d /tmp/z23-telemetry-evaluation.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cp "$subject" "$fixture/subject.c"
# Count malloc/calloc/realloc checks without changing fault behavior. The
# existing hook does not cover strdup, so these are buffer counts only.
cp "$root/platform/modules/base/src/safe_alloc.c" "$fixture/safe_alloc.c"
cat > "$fixture/alloc.c" <<'C'
#define zcl_alloc_fault_should_fail fixture_real_alloc_fault_should_fail
#include "safe_alloc.c"
C
cat > "$fixture/test.c" <<'C'
#include "json/json.h"
#include "util/telemetry_snapshots.h"
#include "base/safe_alloc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static unsigned value_copies;
static size_t allocation_attempts;
bool fixture_real_alloc_fault_should_fail(const char *label);
bool zcl_alloc_fault_should_fail(const char *label)
{
    allocation_attempts++;
    return fixture_real_alloc_fault_should_fail(label);
}
static bool counted_push(struct json_value *obj, const char *key,
                         const struct json_value *child)
{
    if (strcmp(key, "values") == 0) value_copies++;
    return json_push_kv(obj, key, child);
}
#define json_push_kv counted_push
#include "subject.c"
#undef json_push_kv
int64_t clock_now_wall_ms(void) { return 1000000; }
int test_telemetry_render(void);
int test_telemetry_ontology(void);
static union { max_align_t align; unsigned char bytes[65536]; } snapshot;
static void fill(const struct telemetry_domain_schema *schema, int mode)
{
    CHECK(schema->snapshot_size <= sizeof snapshot.bytes);
    memset(&snapshot, 0, sizeof snapshot);
    for (size_t i = 0; i < schema->leaf_count; i++) {
        const struct telemetry_leaf *lf = &schema->leaves[i];
        struct telemetry_leaf_meta *m = (void *)(snapshot.bytes + lf->meta_off);
        *m = (struct telemetry_leaf_meta){
            .presence = (enum telemetry_presence)mode,
            .source = TELEMETRY_SRC_IN_PROCESS, .observed_unix = 1000,
            .reason = "fixture"};
        if (lf->ctype == TLC_I64) {
            int64_t n = (int64_t)i;
            memcpy(snapshot.bytes + lf->value_off, &n, sizeof n);
        } else if (lf->ctype == TLC_BOOL) {
            bool b = i % 2 == 0;
            memcpy(snapshot.bytes + lf->value_off, &b, sizeof b);
        } else if (lf->ctype == TLC_TEXT) {
            snprintf((char *)snapshot.bytes + lf->value_off, TELEMETRY_TEXT_MAX,
                     "fixture text %zu", i);
        }
    }
}
int main(int argc, char **argv)
{
    CHECK(argc == 3);
    unsigned expected = (unsigned)atoi(argv[1]);
    int rounds = atoi(argv[2]);
    CHECK(rounds > 0);
    CHECK(test_telemetry_render() == 0);
    CHECK(test_telemetry_ontology() == 0);
    FILE *output = NULL;
    const char *path = getenv("OUTPUT");
    if (path) { output = fopen(path, "w"); CHECK(output); }
    for (size_t d = 0; d < telemetry_domain_count(); d++) {
        const struct telemetry_domain_schema *schema = telemetry_domain_at(d);
        for (int mode = TELEMETRY_UNSET; mode <= TELEMETRY_TRUNCATED; mode++) {
            fill(schema, mode);
            struct telemetry_domain_verdict verdict;
            unsigned before = value_copies;
            CHECK(telemetry_evaluate(schema, snapshot.bytes, &verdict));
            CHECK(value_copies - before == expected);
            for (int v = TLV_SUMMARY; v <= TLV_FULL; v++) {
                for (size_t g = 0; g <= schema->group_count; g++) {
                    const char *group = g == schema->group_count ? NULL : schema->groups[g].name;
                    struct json_value doc = {0};
                    CHECK(telemetry_render(schema, snapshot.bytes, (enum telemetry_view)v, group, &doc));
                    const struct json_value *health = json_get(&doc, "health");
                    CHECK(strcmp(json_get_str(json_get(health, "state")),
                                 telemetry_health_name(verdict.state)) == 0);
                    if (output) {
                        size_t bytes = json_write(&doc, NULL, 0);
                        char *encoded = malloc(bytes + 1);
                        CHECK(encoded != NULL);
                        CHECK(json_write(&doc, encoded, bytes + 1) == bytes);
                        CHECK(fprintf(output, "%s\n", encoded) > 0);
                        free(encoded);
                    }
                    json_free(&doc);
                }
            }
        }
    }
    if (output) CHECK(fclose(output) == 0);
    fill(&g_sync_schema, TELEMETRY_PRESENT);
    struct telemetry_domain_verdict verdict;
    zcl_alloc_fault_fail_next("json_keys");
    CHECK(!telemetry_evaluate(&g_sync_schema, snapshot.bytes, &verdict));
    zcl_alloc_fault_clear();
    CHECK(telemetry_evaluate(&g_sync_schema, snapshot.bytes, &verdict));
    struct timespec start, end;
    value_copies = 0;
    allocation_attempts = 0;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
    for (int i = 0; i < rounds; i++)
        CHECK(telemetry_evaluate(&g_sync_schema, snapshot.bytes, &verdict));
    CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
    CHECK(value_copies == (unsigned)rounds * expected);
    double ms = (end.tv_sec - start.tv_sec) * 1000.0 + (end.tv_nsec - start.tv_nsec) / 1e6;
    printf("sync_evaluations=%d value_tree_copies=%u buffer_allocation_attempts=%zu wall_ms=%.3f\n",
           rounds, value_copies, allocation_attempts, ms);
    puts("PASS: all domains, presence states, views, groups, allocation refusal and copy budget");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -O2 -Wall -Wextra -Werror)
if [[ ${SANITIZE:-0} == 1 ]]; then
    flags+=(-fsanitize=address,undefined -fno-omit-frame-pointer)
fi
while IFS= read -r dir; do flags+=(-I"$root/$dir"); done < <(
    git -C "$root" ls-files '*include/*.h' | sed 's@/include/.*@/include@' | sort -u
)
sources=("$fixture/test.c" "$root/tests/harness/src/test_telemetry_render.c"
    "$root/tests/harness/src/test_telemetry_ontology.c"
    "$root/platform/modules/json/src/json.c"
    "$fixture/alloc.c" "$root/platform/modules/base/src/log_level.c"
    "$root/platform/modules/util/src/telemetry_reply.c"
    "$root/platform/modules/util/src/telemetry_schemas.c"
    "$root/platform/modules/util/src/telemetry_ontology.c")
"${CC:-cc}" "${flags[@]}" "${sources[@]}" -lm -o "$fixture/test"
if [[ ${ANALYZE:-0} == 1 ]]; then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$subject" -o "$fixture/analyzed.o"
fi
"$fixture/test" "$baseline" "${BENCH_ROUNDS:-2000}"
