#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Receipt hardware observation must not exclude sync counter writers.
# Usage: bash tools/scripts/sync_benchmark_receipt_lock_selftest.sh [--baseline] [--analyze] [source.c]
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
subject=${1:-$root/engine/services/src/sync_benchmark_service.c}
fixture=$(mktemp -d /tmp/z23-receipt-lock.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
# Keep the real state, mutex, counter APIs, receipt builder and reset logic.
# Omit only durable publication, which is outside this isolated experiment.
awk '/^\/\* .*Durable write / { skip = 1; starts++ }
     /^\/\* .*init \/ reset \/ dump / { skip = 0; ends++ }
     !skip { print }
     END { if (starts != 1 || ends != 1) exit 1 }' "$subject" > "$fixture/test.c"
if grep -q '^static pthread_mutex_t g_sb_lock' "$subject"; then
    echo '#define RECEIPT_LOCK g_sb_lock' >> "$fixture/test.c"
else
    echo '#define RECEIPT_LOCK g_sb.lock' >> "$fixture/test.c"
fi
cat >> "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdlib.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static int observations, exclusions, memory_mode;
static bool probing;
static int64_t fake_us = 100000;
int64_t clock_now_monotonic_ns(void) { return fake_us * 1000; }
const char *zcl_build_source_id_sha256(void) { return "fixture-source"; }
const char *zcl_build_commit(void) { return "fixture-commit"; }

static void observe_lock(void)
{
    if (!probing) return;
    observations++;
    int rc = pthread_mutex_trylock(&RECEIPT_LOCK);
    if (rc == EBUSY) { exclusions++; return; }
    CHECK(rc == 0);
    CHECK(pthread_mutex_unlock(&RECEIPT_LOCK) == 0);
    /* Exercise the real writer while the hardware observation is active. */
    sync_benchmark_note_downloaded(17);
}
int hw_profile_physical_cores(void) { observe_lock(); return 8; }
bool os_proc_mem_read(struct os_proc_mem *out)
{
    observe_lock();
    if (memory_mode == 1) return false; /* Leaves output uninitialized. */
    *out = (struct os_proc_mem){.sys_total_bytes = memory_mode == 2 ? 0 : 4096,
                               .rss_bytes = 1024};
    return true;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    for (memory_mode = 0; memory_mode < 3; memory_mode++) {
        for (int complete = 0; complete < 2; complete++) {
            sync_benchmark_reset_for_test();
            sync_benchmark_init(NULL);
            sync_benchmark_set_artifact("fixture-artifact");
            sync_benchmark_note_downloaded(100);
            sync_benchmark_phase_begin(SYNC_BENCH_HEADERS);
            fake_us += 3000;
            sync_benchmark_phase_end(SYNC_BENCH_HEADERS);
            sync_benchmark_mark_ready();
            int previous_exclusions = exclusions;
            struct json_value receipt = {0};
            probing = true;
            CHECK(!sync_benchmark_build_receipt(NULL, false, NULL));
            CHECK(sync_benchmark_build_receipt(&receipt, complete, "fixture-partial"));
            probing = false;
            const struct json_value *hw = json_get(&receipt, "hardware");
            CHECK(json_get_int(json_get(hw, "physical_cores")) == 8);
            const struct json_value *ram = json_get(hw, "total_ram_bytes");
            CHECK(memory_mode == 0 ? json_get_int(ram) == 4096 : json_is_null(ram));
            CHECK(strcmp(json_get_str(json_get(hw, "build_commit")), "fixture-commit") == 0);
            CHECK(json_get_bool(json_get(&receipt, "complete")) == (bool)complete);
            CHECK(complete ? json_is_null(json_get(&receipt, "incomplete_reason")) :
                  strcmp(json_get_str(json_get(&receipt, "incomplete_reason")), "fixture-partial") == 0);
            CHECK(strcmp(json_get_str(json_get(&receipt, "artifact_id")), "fixture-artifact") == 0);
            const struct json_value *times = json_get(&receipt, "timings_ms");
            CHECK(json_get_int(json_get(times, "headers")) == 3);
            CHECK(json_get_int(json_get(times, "t_ready")) == 3);
            CHECK(json_is_null(json_get(times, "t_sovereign")));
            CHECK(json_is_null(json_get(times, "install")));
            const struct json_value *resources = json_get(&receipt, "resources");
            int successes = 2 - (exclusions - previous_exclusions);
            CHECK(json_get_int(json_get(resources, "bytes_downloaded")) == 100 + 17 * successes);
            CHECK(json_is_null(json_get(resources, "bytes_reused")));
            json_free(&receipt);
        }
    }
    printf("receipts=6 hardware_observations=%d counter_writer_exclusions=%d\n",
           observations, exclusions);
    CHECK(observations == 12);
    if (!baseline) CHECK(exclusions == 0);
    puts(baseline ? "BASELINE: receipt lock overlap measured" :
         "PASS: hardware reads allow counter updates; receipt fields and nulls retained");
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
"$fixture/test" "$baseline"
