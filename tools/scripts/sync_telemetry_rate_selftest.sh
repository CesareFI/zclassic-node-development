#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise the real rate derivation against a captured snapshot and changing
# stage counters. No node, network, datadir or validation work is started.
# Usage: bash tools/scripts/sync_telemetry_rate_selftest.sh [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
source_file=${1:-$root/engine/services/src/sync_telemetry_fill.c}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-sync-rate.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include "util/telemetry_snapshots.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static unsigned reads;
/* External linkage keeps the baseline probes warning-clean after the fix
 * removes all calls. Values deliberately differ from the captured sample. */
#define GETTER(name) int64_t name##_stage_step_us_ewma(void) \
    { reads++; return 900000 + reads; }
GETTER(header_admit)
GETTER(validate_headers)
GETTER(body_fetch)
GETTER(body_persist)
GETTER(utxo_apply)
GETTER(tip_finalize)
int64_t telemetry_now_unix(void) { return 123; }
void telemetry_set_text_impl(char *dst, size_t size,
                             struct telemetry_leaf_meta *meta,
                             const char *value, enum telemetry_source src)
{
    CHECK(strlen(value) < size);
    memcpy(dst, value, strlen(value) + 1);
    *meta = (struct telemetry_leaf_meta){
        .presence = TELEMETRY_PRESENT, .source = src,
        .observed_unix = telemetry_now_unix(), .reason = ""
    };
}
C
# Fail if the source boundaries change instead of passing an empty fixture.
awk '
    /^#define SYNC_TL_BPS_SCALE / { copy = 1; starts++ }
    /^static void fill_frontier\(/ { copy = 0; ends++ }
    /^static void fill_rate\(/ { copy = 1; starts++ }
    /^bool sync_dump_state_fill\(/ { copy = 0; ends++ }
    copy { print }
    END { if (starts != 2 || ends != 2) exit 1 }
' "$source_file" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
int main(void)
{
    struct sync_snapshot s = {0};
    s.header_admit_step_us_ewma = 10;
    s.validate_headers_step_us_ewma = 20;
    s.body_fetch_step_us_ewma = 1000;
    s.body_persist_step_us_ewma = 30;
    s.utxo_apply_step_us_ewma = 100;
    s.tip_finalize_step_us_ewma = 200;
    fill_rate(&s);
    printf("extra_stage_reads=%u slowest=%s step_us=%lld\n", reads,
           s.slowest_stage, (long long)s.slowest_stage_step_us);
    CHECK(reads == 0);
    CHECK(strcmp(s.slowest_stage, "body_fetch") == 0);
    CHECK(s.slowest_stage_step_us == 1000);
    CHECK(s.tip_finalize_blocks_per_sec_x1000 == 5000000);
    CHECK(s.utxo_apply_blocks_per_sec_x1000 == 10000000);
    CHECK(s.tip_finalize_blocks_per_sec_x1000_meta.source == TELEMETRY_SRC_DERIVED);
    CHECK(s.slowest_stage_meta.presence == TELEMETRY_PRESENT);

    /* Equal maxima keep the earlier rung, exactly as before. */
    s.header_admit_step_us_ewma = 1000;
    fill_rate(&s);
    CHECK(strcmp(s.slowest_stage, "header_admit") == 0);

    /* Pre-start and invalid nonpositive samples cannot publish a rate. */
    s = (struct sync_snapshot){0};
    s.tip_finalize_step_us_ewma = -1;
    fill_rate(&s);
    CHECK(s.tip_finalize_blocks_per_sec_x1000_meta.presence == TELEMETRY_UNAVAILABLE);
    CHECK(s.utxo_apply_blocks_per_sec_x1000_meta.presence == TELEMETRY_UNAVAILABLE);
    CHECK(s.slowest_stage_meta.presence == TELEMETRY_UNAVAILABLE);
    CHECK(s.slowest_stage_step_us_meta.presence == TELEMETRY_UNAVAILABLE);
    CHECK(strcmp(s.slowest_stage_meta.reason, "no_stage_has_stepped") == 0);
    s.utxo_apply_step_us_ewma = 1;
    fill_rate(&s);
    CHECK(s.utxo_apply_blocks_per_sec_x1000 == 1000000000);
    CHECK(strcmp(s.slowest_stage, "utxo_apply") == 0);
    CHECK(reads == 0);
    puts("sync telemetry rate selftest: PASS");
    return 0;
}
C
flags=(-std=c23 -O2 -Wall -Wextra -Werror
       -I"$root/platform/modules/util/include")
"${CC:-cc}" "${flags[@]}" "$fixture/test.c" -o "$fixture/test"
"$fixture/test"
if [[ ${ANALYZE:-0} == 1 ]]; then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -fsyntax-only "$fixture/test.c"
fi
