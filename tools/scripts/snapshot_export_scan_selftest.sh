#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Run the real export CLI against an in-memory coins fixture and a recording
# writer. Measure the real setinfo query separately from artifact generation.
# Usage: snapshot_export_scan_selftest.sh [--baseline] [source.c]
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
baseline=0
if [[ ${1:-} == --baseline ]]; then baseline=1; shift; fi
source_file=${1:-$root/tools/snapshot_from_coinskv.c}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-export-scan.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
cp "$source_file" "$fixture/subject.c"
cat > "$fixture/test.c" <<'C'
#define main export_main
#include "subject.c"
#undef main
#include <time.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static sqlite3 *fixture_db;
static int opens, scans, writes, collects, releases, mode;
static int64_t scan_steps;
static double scan_ms;
static int observed_step(sqlite3_stmt *stmt)
{
    int rc = sqlite3_step(stmt);
    scan_steps += sqlite3_stmt_status(stmt, SQLITE_STMTSTATUS_FULLSCAN_STEP, 0);
    return rc;
}
#define sqlite3_step observed_step
C
# Use the actual aggregation query, including its error paths.
awk '/^bool coins_kv_setinfo_sqlite\(/ { copy=1 }
     copy { print }
     copy && /^}/ { exit }' "$root/engine/modules/storage/src/coins_kv.c" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
#undef sqlite3_step
bool coins_kv_setinfo(sqlite3 *db, int64_t *txs, int64_t *count, int64_t *supply)
{
    struct timespec start, end;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &start) == 0);
    scans++;
    bool ok = coins_kv_setinfo_sqlite(db, txs, count, supply);
    CHECK(clock_gettime(CLOCK_MONOTONIC, &end) == 0);
    scan_ms += (end.tv_sec - start.tv_sec) * 1000.0 +
               (end.tv_nsec - start.tv_nsec) / 1e6;
    return ok;
}
bool progress_store_open(const char *path)
{
    CHECK(strcmp(path, "fixture") == 0);
    opens++;
    return mode != 1;
}
sqlite3 *progress_store_db(void) { return mode == 2 ? NULL : fixture_db; }
bool snapshot_shielded_collect_from_db(sqlite3 *db, int64_t h,
                                      struct snapshot_shielded *out)
{
    CHECK(db == fixture_db && h == 42);
    collects++;
    memset(out, 0, sizeof(*out));
    return mode != 3;
}
void snapshot_shielded_free_collected(struct snapshot_shielded *s)
{
    CHECK(s != NULL);
    releases++;
}
bool coins_kv_snapshot_write(sqlite3 *db, const char *path, int32_t h,
                            const uint8_t hash[32],
                            const struct snapshot_shielded *shielded,
                            uint8_t digest[32], uint64_t *count, int64_t *supply)
{
    CHECK(db == fixture_db && strcmp(path, "fixture.out") == 0 && h == 42);
    for (int i = 0; i < 32; i++) CHECK(hash[i] == 31 - i);
    CHECK((shielded != NULL) == (collects != 0));
    writes++;
    memset(digest, 0xab, 32);
    *count = 100000;
    *supply = 500000;
    return mode != 4;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    bool baseline = strcmp(argv[1], "1") == 0;
    CHECK(sqlite3_open(":memory:", &fixture_db) == SQLITE_OK);
    CHECK(sqlite3_exec(fixture_db,
        "CREATE TABLE coins(txid BLOB, vout INTEGER, value INTEGER,"
        "PRIMARY KEY(txid,vout)) WITHOUT ROWID;"
        "WITH RECURSIVE rows(n) AS (VALUES(1) UNION ALL "
        "SELECT n+1 FROM rows WHERE n<100000) "
        "INSERT INTO coins SELECT CAST(printf('%032d',n/2) AS BLOB),n%2,5 FROM rows;",
        NULL, NULL, NULL) == SQLITE_OK);
    char hash[] = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";
    char *args[] = {"snapshot_from_coinskv", "fixture", "42", hash,
                    "fixture.out", "--shielded", NULL};
    for (int shielded = 0; shielded <= 1; shielded++) {
        for (mode = 0; mode <= 4; mode++) {
            opens = scans = writes = collects = releases = 0;
            scan_steps = 0;
            scan_ms = 0;
            int rc = export_main(5 + shielded, args);
            bool collected = shielded && mode != 1 && mode != 2;
            bool written = mode != 1 && mode != 2 && !(shielded && mode == 3);
            CHECK(opens == 1);
            CHECK(collects == (int)collected);
            CHECK(writes == (int)written);
            CHECK(releases == (int)(collected && mode != 3));
            CHECK(rc == (written && mode != 4 ? 0 : 1));
            CHECK(scans == (baseline && mode != 1 && mode != 2 ? 1 : 0));
            CHECK(scan_steps == (scans ? 99999 : 0));
            if (mode == 0)
                printf("shielded=%d diagnostic_scans=%d fullscan_steps=%lld scan_ms=%.3f\n",
                       shielded, scans, (long long)scan_steps, scan_ms);
        }
    }
    opens = 0;
    CHECK(export_main(1, args) == 2);
    args[5] = "--invalid";
    CHECK(export_main(6, args) == 2);
    args[3] = "bad";
    CHECK(export_main(5, args) == 2);
    hash[0] = 'z'; args[3] = hash;
    CHECK(export_main(5, args) == 2);
    CHECK(opens == 0);
    CHECK(sqlite3_close(fixture_db) == SQLITE_OK);
    puts("PASS: export dispatch, shielded cleanup, failures and diagnostic scan budget");
    return 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic
       -I"$root/platform/modules/base/include"
       -I"$root/engine/modules/storage/include" -I"$root/vendor/include")
if [[ ${SANITIZE:-0} == 1 ]]; then
    flags+=(-fsanitize=address,undefined -fno-omit-frame-pointer)
fi
read -r -a sqlite_libs <<< "${SQLITE_LIBS:-$root/vendor/lib/libsqlite3.a -lpthread -ldl -lm}"
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" "${sqlite_libs[@]}" -o "$fixture/test"
if [[ ${ANALYZE:-0} == 1 ]]; then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
if ! "$fixture/test" "$baseline" > "$fixture/result" 2> "$fixture/messages"; then
    cat "$fixture/result" "$fixture/messages" >&2
    exit 1
fi
cat "$fixture/result"
# Success still reports the writer's actual outputs, never pre-scan totals.
grep -q 'WROTE fixture.out height=42 count=100000 supply=500000 sha3=abababab' "$fixture/messages"
grep -q 'coins_kv_snapshot_write FAILED' "$fixture/messages"
