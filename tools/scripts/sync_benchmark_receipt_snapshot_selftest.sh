#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# JSON receipt construction must neither exclude writers nor mix observations.
# Usage: bash tools/scripts/sync_benchmark_receipt_snapshot_selftest.sh [--baseline] [--bench] [--analyze] [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
baseline=0 analyze=0 bench=0
while [[ ${1:-} == --* ]]; do
    case $1 in
        --baseline) baseline=1 ;;
        --bench) bench=1 ;;
        --analyze) analyze=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
subject=${1:-$root/engine/services/src/sync_benchmark_service.c}
fixture=$(mktemp -d /tmp/z23-receipt-snapshot.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include "json/json.h"
#include <pthread.h>
static void observed_push_int(struct json_value *, const char *, int64_t);
static int measured_lock(pthread_mutex_t *);
static int measured_unlock(pthread_mutex_t *);
#define json_push_kv_int observed_push_int
#define pthread_mutex_lock measured_lock
#define pthread_mutex_unlock measured_unlock
C
# Keep the real receipt, state and writer APIs; durable filesystem publication
# is outside this isolated measurement. Compile against the real JSON library.
awk '/^\/\* .*Durable write / { skip = 1; starts++ }
     /^\/\* .*init \/ reset \/ dump / { skip = 0; ends++ }
     !skip { print }
     END { if (starts != 1 || ends != 1) exit 1 }' "$subject" >> "$fixture/test.c"
# Support the pre-change mutex layout for the failing baseline witness.
if grep -q '^static pthread_mutex_t g_sb_lock' "$subject"; then
    echo '#define RECEIPT_LOCK g_sb_lock' >> "$fixture/test.c"
else
    echo '#define RECEIPT_LOCK g_sb.lock' >> "$fixture/test.c"
fi
cat >> "$fixture/test.c" <<'C'
#undef json_push_kv_int
#undef pthread_mutex_lock
#undef pthread_mutex_unlock
#include <errno.h>
#include <stdlib.h>
#include <time.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static int attempts, exclusions;
static bool probing, mutate;
static bool measuring;
static int64_t locked_at, held_ns;
static int64_t fake_us = 100000;
static int64_t measured_ns(void)
{
    struct timespec ts;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &ts) == 0);
    return (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}
static int measured_lock(pthread_mutex_t *lock)
{
    int rc = pthread_mutex_lock(lock);
    if (measuring && rc == 0) locked_at = measured_ns();
    return rc;
}
static int measured_unlock(pthread_mutex_t *lock)
{
    if (measuring) held_ns += measured_ns() - locked_at;
    return pthread_mutex_unlock(lock);
}
int64_t clock_now_monotonic_ns(void) { return fake_us * 1000; }
const char *zcl_build_source_id_sha256(void) { return "fixture-source"; }
const char *zcl_build_commit(void) { return "fixture-commit"; }
int hw_profile_physical_cores(void) { return 8; }
bool os_proc_mem_read(struct os_proc_mem *out)
{
    *out = (struct os_proc_mem){.sys_total_bytes = 4096, .rss_bytes = 1024};
    return true;
}
static void observed_push_int(struct json_value *out, const char *key, int64_t value)
{
    if (probing) {
        attempts++;
        int rc = pthread_mutex_trylock(&RECEIPT_LOCK);
        if (rc == EBUSY) {
            exclusions++;
        } else {
            CHECK(rc == 0);
            CHECK(pthread_mutex_unlock(&RECEIPT_LOCK) == 0);
            /* Deterministic interleaving: these real writer APIs run while
             * JSON construction is in progress. No timing race in the gate. */
            if (mutate) {
                mutate = false;
                sync_benchmark_note_downloaded(17);
                sync_benchmark_note_reused(19);
                sync_benchmark_note_redownloaded(23);
                sync_benchmark_set_artifact("next-artifact");
                fake_us += 5000;
                sync_benchmark_phase_end(SYNC_BENCH_INSTALL);
                sync_benchmark_mark_ready();
                sync_benchmark_mark_sovereign();
            }
        }
    }
    json_push_kv_int(out, key, value);
}
static void check_receipt(const struct json_value *out, bool updated)
{
    const struct json_value *timings = json_get(out, "timings_ms");
    const struct json_value *resources = json_get(out, "resources");
    CHECK(json_get_int(json_get(timings, "headers")) == 3);
    CHECK(json_get_int(json_get(timings, "t_ready")) == (updated ? 8 : 3));
    CHECK(updated ? json_get_int(json_get(timings, "t_sovereign")) == 8 :
                    json_is_null(json_get(timings, "t_sovereign")));
    CHECK(updated ? json_get_int(json_get(timings, "install")) == 5 :
                    json_is_null(json_get(timings, "install")));
    CHECK(json_get_int(json_get(resources, "bytes_downloaded")) == (updated ? 117 : 100));
    CHECK(json_get_int(json_get(resources, "bytes_reused")) == (updated ? 219 : 200));
    CHECK(json_get_int(json_get(resources, "bytes_redownloaded")) == (updated ? 323 : 300));
    CHECK(json_get_int(json_get(resources, "peak_rss_bytes")) == 1024);
    CHECK(json_is_null(json_get(resources, "disk_write_bytes")));
    CHECK(strcmp(json_get_str(json_get(out, "artifact_id")),
                 updated ? "next-artifact" : "fixture-artifact") == 0);
    const struct json_value *reasons = json_get(out, "null_reasons");
    if (!updated)
        CHECK(strcmp(json_get_str(json_get(reasons, "install")),
                     "phase_started_but_not_completed") == 0);
}
int main(int argc, char **argv)
{
    CHECK(argc == 3);
    bool baseline = strcmp(argv[1], "1") == 0;
    for (int complete = 0; complete < 2; complete++) {
        fake_us = 100000;
        sync_benchmark_reset_for_test();
        sync_benchmark_init(NULL);
        sync_benchmark_set_artifact("fixture-artifact");
        sync_benchmark_note_downloaded(100);
        sync_benchmark_note_reused(200);
        sync_benchmark_note_redownloaded(300);
        sync_benchmark_phase_begin(SYNC_BENCH_HEADERS);
        fake_us += 3000;
        sync_benchmark_phase_end(SYNC_BENCH_HEADERS);
        sync_benchmark_mark_ready();
        sync_benchmark_phase_begin(SYNC_BENCH_INSTALL);
        struct json_value receipt = {0};
        mutate = probing = true;
        CHECK(sync_benchmark_build_receipt(&receipt, complete, "fixture-partial"));
        probing = false;
        check_receipt(&receipt, false);
        CHECK(json_get_bool(json_get(&receipt, "complete")) == (bool)complete);
        json_free(&receipt);
        /* A later receipt observes the admitted changes, never a mixture
         * of pre- and post-update counters/timings in the original receipt. */
        CHECK(sync_benchmark_build_receipt(&receipt, complete, "fixture-partial"));
        check_receipt(&receipt, !mutate);
        json_free(&receipt);
    }
    printf("receipts=2 serialization_writer_attempts=%d exclusions=%d\n", attempts, exclusions);
    CHECK(attempts > 0);
    if (!baseline) CHECK(exclusions == 0);
    if (strcmp(argv[2], "1") == 0) {
        sync_benchmark_reset_for_test();
        sync_benchmark_init(NULL);
        sync_benchmark_note_downloaded(100);
        for (int run = 0; run < 3; run++) {
            held_ns = 0;
            measuring = true;
            int64_t started = measured_ns();
            for (int i = 0; i < 10000; i++) {
                struct json_value receipt = {0};
                CHECK(sync_benchmark_build_receipt(&receipt, false, "fixture-partial"));
                json_free(&receipt);
            }
            int64_t wall_ns = measured_ns() - started;
            measuring = false;
            printf("run=%d receipts=10000 mutex_held_ms=%.3f wall_ms=%.3f\n",
                   run + 1, (double)held_ns / 1e6, (double)wall_ns / 1e6);
        }
    }
    puts(baseline ? "BASELINE: serialization lock overlap measured" :
         "PASS: JSON construction admits writers and retains a coherent observation");
    return 0;
}
C
flags=(-std=c23 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror -pthread
    -I"$root/engine/services/include" -I"$root/platform/modules/json/include"
    -I"$root/platform/modules/platform/include" -I"$root/platform/modules/util/include"
    -I"$root/platform/modules/base/include")
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" \
    "$root/platform/modules/json/src/json.c" \
    "$root/platform/modules/base/src/safe_alloc.c" -lm -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
"${CC:-cc}" "${flags[@]}" -fsyntax-only "$subject"
"$fixture/test" "$baseline" "$bench"
