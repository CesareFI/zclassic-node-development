#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Real sync command/render/evaluator, isolated snapshot and reply transport.
# Usage: bash tools/scripts/telemetry_sync_summary_selftest.sh [--baseline] [source.c]
# BENCH_ROUNDS controls repeated summary calls; OUTPUT records deterministic replies.
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
subject=${1:-$root/tools/command/native_telemetry_sync_command.c}
fixture=$(mktemp -d /tmp/z23-sync-summary.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cp "$subject" "$fixture/subject.c"
cat > "$fixture/test.c" <<'C'
#include "util/telemetry_render.h"
#include "base/safe_alloc.h"
#include <stdlib.h>
#include <time.h>
static unsigned explicit_evaluations;
static bool counted_evaluate(const struct telemetry_domain_schema *s,
                             const void *snap, struct telemetry_domain_verdict *v)
{
    explicit_evaluations++;
    return telemetry_evaluate(s, snap, v);
}
#define telemetry_evaluate counted_evaluate
#include "subject.c"
#undef telemetry_evaluate
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static int mode;
static unsigned fills;
int64_t clock_now_wall_ms(void) { return 1000000; }
void chain_params_select(enum chain_network network) { CHECK(network == CHAIN_MAIN); }
bool sync_dump_state_fill(struct sync_snapshot *s)
{
    fills++;
    if (mode == 3) return false;
    memset(s, 0, sizeof *s);
    for (size_t i = 0; i < g_sync_schema.leaf_count; i++) {
        const struct telemetry_leaf *lf = &g_sync_schema.leaves[i];
        struct telemetry_leaf_meta *m = (void *)((char *)s + lf->meta_off);
        *m = (struct telemetry_leaf_meta){.presence = TELEMETRY_PRESENT,
            .source = TELEMETRY_SRC_IN_PROCESS, .observed_unix = 1000, .age_ms = 0};
        if (lf->ctype == TLC_I64) {
            int64_t n = strstr(lf->key, "_cursor") ? 100 : 0;
            memcpy((char *)s + lf->value_off, &n, sizeof n);
        } else if (lf->ctype == TLC_BOOL) {
            bool b = true;
            memcpy((char *)s + lf->value_off, &b, sizeof b);
        }
        if (mode == 1 && strcmp(lf->key, "body_persist_cursor") == 0) {
            int64_t n = 200; /* A real unhealthy ladder inversion. */
            memcpy((char *)s + lf->value_off, &n, sizeof n);
        }
        if (mode == 4 || (mode == 2 && strcmp(lf->key, "body_persist_cursor") == 0))
            m->presence = TELEMETRY_UNSET;
    }
    return true;
}
void zcl_command_reply_fail(struct zcl_command_reply *r,
    enum zcl_command_status status, enum zcl_command_exit code,
    const char *error, const char *phase, bool retryable, bool mutated,
    const char *message, const char *evidence)
{
    (void)phase; (void)retryable; (void)mutated; (void)evidence;
    CHECK(message && message[0]);
    r->status = status; r->exit_code = code;
    snprintf(r->error.code, sizeof r->error.code, "%s", error);
}
bool zcl_command_reply_add_next(struct zcl_command_reply *r, const char *command,
                               const char *input, const char *reason)
{
    CHECK(r->next_count < ZCL_COMMAND_MAX_NEXT);
    struct zcl_command_next *n = &r->next[r->next_count++];
    snprintf(n->command, sizeof n->command, "%s", command);
    snprintf(n->input_json, sizeof n->input_json, "%s", input);
    snprintf(n->reason, sizeof n->reason, "%s", reason);
    return true;
}
static void summary(const char *view, unsigned expected, FILE *output)
{
    struct zcl_command_request request = {.view = view};
    struct zcl_command_reply reply = {0};
    unsigned before = explicit_evaluations, before_fills = fills;
    zcl_native_handle_telemetry_sync_summary(&request, &reply);
    CHECK(fills == before_fills + 1);
    CHECK(explicit_evaluations == before + expected);
    if (reply.exit_code) fprintf(stderr, "mode=%d error=%s\n", mode, reply.error.code);
    CHECK(reply.exit_code == ZCL_COMMAND_EXIT_OK);
    const char *health = json_get_str(json_get(json_get(&reply.data, "health"), "state"));
    CHECK(health != NULL);
    if (mode == 0) CHECK(strcmp(health, "ok") == 0);
    if (mode == 1) CHECK(strcmp(health, "degraded") == 0);
    if (mode == 2) CHECK(strcmp(health, "unknown") == 0);
    CHECK(json_get(&reply.data, "bottleneck") != NULL);
    CHECK(reply.next_count > 0);
    if (output) {
        char encoded[32768];
        CHECK(json_write(&reply.data, encoded, sizeof encoded) > 0);
        fprintf(output, "%d %s %s\n", mode, view, encoded);
        for (size_t i = 0; i < reply.next_count; i++)
            fprintf(output, "%s %s %s\n", reply.next[i].command,
                    reply.next[i].input_json, reply.next[i].reason);
    }
    json_free(&reply.data);
}
int main(int argc, char **argv)
{
    CHECK(argc == 3);
    unsigned expected = (unsigned)atoi(argv[1]);
    int rounds = atoi(argv[2]);
    CHECK(rounds > 0);
    FILE *output = NULL;
    const char *path = getenv("OUTPUT");
    if (path) { output = fopen(path, "w"); CHECK(output); }
    const char *views[] = {"summary", "normal", "full", "unknown"};
    for (mode = 0; mode < 3; mode++)
        for (size_t i = 0; i < sizeof views / sizeof views[0]; i++)
            summary(views[i], expected, output);
    if (output) CHECK(fclose(output) == 0);
    mode = 3;
    struct zcl_command_request request = {.view = "summary"};
    struct zcl_command_reply reply = {0};
    zcl_native_handle_telemetry_sync_summary(&request, &reply);
    CHECK(strcmp(reply.error.code, "SNAPSHOT_UNAVAILABLE") == 0);
    json_free(&reply.data);
    mode = 4; /* The unchanged budget must refuse an oversized provenance plane. */
    reply = (struct zcl_command_reply){0};
    zcl_native_handle_telemetry_sync_summary(&request, &reply);
    CHECK(strcmp(reply.error.code, "REPLY_TOO_LARGE") == 0);
    json_free(&reply.data);
    mode = 0;
    reply = (struct zcl_command_reply){0};
    zcl_alloc_fault_fail_next("json_keys");
    zcl_native_handle_telemetry_sync_summary(&request, &reply);
    CHECK(reply.exit_code != ZCL_COMMAND_EXIT_OK);
    CHECK(reply.error.code[0]);
    zcl_alloc_fault_clear();
    json_free(&reply.data);
    /* Stage projections still request their independent verdict. */
    reply = (struct zcl_command_reply){0};
    unsigned before = explicit_evaluations;
    zcl_native_handle_telemetry_sync_stages(&request, &reply);
    CHECK(explicit_evaluations == before + 1);
    if (reply.exit_code) fprintf(stderr, "mode=%d error=%s\n", mode, reply.error.code);
    CHECK(reply.exit_code == ZCL_COMMAND_EXIT_OK);
    json_free(&reply.data);
    struct json_value input = {0};
    json_set_object(&input);
    CHECK(json_push_kv_str(&input, "stage", "body_fetch"));
    request.input = &input;
    reply = (struct zcl_command_reply){0};
    before = explicit_evaluations;
    zcl_native_handle_telemetry_sync_stage(&request, &reply);
    CHECK(explicit_evaluations == before + 1);
    CHECK(reply.exit_code == ZCL_COMMAND_EXIT_OK);
    CHECK(json_get(&reply.data, "leaves") != NULL);
    json_free(&reply.data);
    json_free(&input);
    struct timespec start, end;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
    before = explicit_evaluations;
    for (int i = 0; i < rounds; i++) summary("summary", expected, NULL);
    CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
    double ms = (end.tv_sec - start.tv_sec) * 1000.0 + (end.tv_nsec - start.tv_nsec) / 1e6;
    printf("summary_calls=%d redundant_evaluations=%u wall_ms=%.3f\n",
           rounds, explicit_evaluations - before, ms);
    puts("PASS: health, missing observations, views, errors and stage evaluation retained");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -O2 -Wall -Wextra -Werror -I"$root/tools")
if [[ ${SANITIZE:-0} == 1 ]]; then
    flags+=(-fsanitize=address,undefined -fno-omit-frame-pointer)
fi
while IFS= read -r dir; do flags+=(-I"$root/$dir"); done < <(
    git -C "$root" ls-files '*include/*.h' | sed 's@/include/.*@/include@' | sort -u
)
sources=("$fixture/test.c" "$root/platform/modules/json/src/json.c"
    "$root/platform/modules/base/src/safe_alloc.c" "$root/platform/modules/base/src/log_level.c"
    "$root/platform/modules/util/src/telemetry_render.c"
    "$root/platform/modules/util/src/telemetry_reply.c"
    "$root/platform/modules/util/src/telemetry_schemas.c"
    "$root/platform/modules/util/src/telemetry_ontology.c")
"${CC:-cc}" "${flags[@]}" "${sources[@]}" -lm -o "$fixture/test"
if [[ ${ANALYZE:-0} == 1 ]]; then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$subject" -o "$fixture/analyzed.o"
fi
"$fixture/test" "$baseline" "${BENCH_ROUNDS:-1000}"
