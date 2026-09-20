#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise real benchmark setup under a fixed clock; no node or RPC is run.
# Usage: bash tools/scripts/bench_fresh_sync_datadir_selftest.sh [--baseline] [--analyze] [source.c]
set -euo pipefail
umask 022
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
source_file=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-bench-datadir.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#define CHECK(x) do { if (!(x)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); \
} } while (0)
static const char *fixture_home;
static bool fail_time;
static const char *fixture_getenv(const char *key)
{
    CHECK(strcmp(key, "HOME") == 0);
    return fixture_home;
}
static time_t platform_time_wall_time_t(void) { return 0; }
static struct tm *fixture_localtime(const time_t *value)
{
    CHECK(*value == 0);
    static struct tm fixed = { .tm_year = 126, .tm_mon = 8, .tm_mday = 19 };
    if (fail_time) errno = EOVERFLOW;
    return fail_time ? NULL : &fixed;
}
static int fixture_access(const char *path, int mode)
{
    CHECK(strcmp(path, "build/bin/zclassic23") == 0 && mode == X_OK);
    return 0;
}
#define getenv fixture_getenv
#define localtime fixture_localtime
#define access fixture_access
C
if grep -q '^static bool benchmark_paths(' "$source_file"; then
    sed -n '/^static bool benchmark_paths(/,/^}/p' "$source_file" >> "$fixture/test.c"
    cat >> "$fixture/test.c" <<'C'
static int setup(char *output, size_t size)
{
    char datadir[256], binary[256], logfile[300];
    if (!benchmark_paths(datadir, sizeof(datadir), binary, sizeof(binary),
                         logfile, sizeof(logfile))) return 1;
C
else
    cat >> "$fixture/test.c" <<'C'
static int setup(char *output, size_t size)
{
C
    awk '
        /\/\* Build datadir path/ { copy = 1; starts++ }
        /\/\* Copy SSL certs/ { copy = 0; ends++ }
        copy { print }
        END { if (starts != 1 || ends != 1) exit 1 }
    ' "$source_file" >> "$fixture/test.c"
fi
cat >> "$fixture/test.c" <<'C'
    CHECK(snprintf(output, size, "%s", datadir) < (int)size);
    return 0;
}
#undef getenv
#undef localtime
#undef access
int main(int argc, char **argv)
{
    CHECK(argc == 3);
    bool baseline = strcmp(argv[2], "1") == 0;
    fixture_home = argv[1];
    /* Both launches see exactly the same second. A leftover run is live
     * filesystem state, not a mock of directory creation. */
    char first[256], second[256], marker[300];
    CHECK(setup(first, sizeof(first)) == 0);
    CHECK(snprintf(marker, sizeof(marker), "%s/previous-run", first) < (int)sizeof(marker));
    FILE *f = fopen(marker, "w");
    CHECK(f != NULL && fputs("fixture", f) >= 0 && fclose(f) == 0);
    CHECK(setup(second, sizeof(second)) == 0);
    bool shared = strcmp(first, second) == 0;
    printf("same_second_launches=2 distinct_datadirs=%d reused_previous_run=%d\n",
           shared ? 1 : 2, shared);
    CHECK(baseline || !shared);
    struct stat st;
    CHECK(stat(marker, &st) == 0 && st.st_size == 7);
    if (baseline) return 0;
    CHECK(stat(first, &st) == 0 && S_ISDIR(st.st_mode) && (st.st_mode & 0777) == 0700);
    CHECK(stat(second, &st) == 0 && S_ISDIR(st.st_mode) && (st.st_mode & 0777) == 0700);
    CHECK(snprintf(marker, sizeof(marker), "%s/previous-run", second) < (int)sizeof(marker));
    CHECK(access(marker, F_OK) != 0);
    /* Setup failures must refuse before the caller starts a node. */
    fixture_home = NULL;
    CHECK(setup(second, sizeof(second)) != 0);
    fixture_home = "";
    CHECK(setup(second, sizeof(second)) != 0);
    char long_home[512];
    memset(long_home, 'x', sizeof(long_home) - 1);
    long_home[sizeof(long_home) - 1] = '\0';
    fixture_home = long_home;
    CHECK(setup(second, sizeof(second)) != 0);
    fixture_home = first;
    fail_time = true;
    CHECK(setup(second, sizeof(second)) != 0);
    fail_time = false;
    /* A regular file cannot be a parent directory. */
    CHECK(snprintf(marker, sizeof(marker), "%s/previous-run", first) < (int)sizeof(marker));
    fixture_home = marker;
    CHECK(setup(second, sizeof(second)) != 0);
    puts("PASS: unique cold datadirs, preserved prior run, private mode, early setup refusal");
    return 0;
}
C
flags=(-std=c23 -D_DEFAULT_SOURCE -Wall -Wextra -Werror)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
fi
timeout 10 "$fixture/test" "$fixture" "$baseline"
