#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Repeated startup trials must reserve fresh state before starting the clock.
# Real filesystem operations stay under one disposable fixture; boot is stubbed.
# Usage: bash tools/scripts/speedrun_datadir_selftest.sh [--analyze] [source.c]
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
analyze=0
if [[ ${1:-} == --analyze ]]; then analyze=1; shift; fi
source_file=${1:-$root/tools/speedrun.c}
scratch=$(mktemp -d /tmp/zcl-speedrun-datadir.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/fixture.c" <<'C'
#include <dirent.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #expr); exit(2); \
} } while (0)
static const char *fixture_root;
static bool refuse;
static unsigned boot_calls, clock_reads;
static char redirected[256];
static const char prefix[] = "/tmp/zcl23-speedrun-";
static void redirect_path(const char *path)
{
    CHECK(strncmp(path, prefix, sizeof(prefix) - 1) == 0);
    CHECK(snprintf(redirected, sizeof(redirected), "%s/%s",
                   fixture_root, path + sizeof(prefix) - 1) < (int)sizeof(redirected));
}
/* Both entry points use the real filesystem. The old PID-only directory is
 * mapped to the same location on each trial; mkdtemp retains its real suffix. */
int fixture_mkdir(const char *path, mode_t mode)
{
    redirect_path(path);
    if (refuse) { errno = ENOSPC; return -1; }
    return mkdir(redirected, mode);
}
char *fixture_mkdtemp(char *path)
{
    redirect_path(path);
    if (refuse) { errno = ENOSPC; return NULL; }
    if (!mkdtemp(redirected)) return NULL;
    CHECK(strlen(redirected) < 256);
    strcpy(path, redirected);
    return path;
}
pid_t fixture_getpid(void) { return 42; }
#define mkdir fixture_mkdir
#define mkdtemp fixture_mkdtemp
#define getpid fixture_getpid
#define main speedrun_main
C
printf '#include "%s"\n' "$source_file" >> "$scratch/fixture.c"
cat >> "$scratch/fixture.c" <<'C'
#undef main
#undef getpid
#undef mkdtemp
#undef mkdir
int64_t clock_now_monotonic_ns(void)
{
    return (int64_t)++clock_reads * 1000000000;
}
void app_context_defaults(struct app_context *ctx)
{
    memset(ctx, 0, sizeof(*ctx));
}
bool app_init(struct app_context *ctx)
{
    boot_calls++;
    CHECK(!refuse && clock_reads == 1);
    /* Only the old implementation still passes its unmapped PID path. */
    const char *dir = ctx->datadir;
    if (strncmp(dir, prefix, sizeof(prefix) - 1) == 0) dir = redirected;
    DIR *d = opendir(dir);
    CHECK(d != NULL);
    struct dirent *entry;
    while ((entry = readdir(d)) != NULL)
        CHECK(strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0);
    CHECK(closedir(d) == 0);
    char state[300];
    CHECK(snprintf(state, sizeof(state), "%s/prior-trial", dir) < (int)sizeof(state));
    FILE *f = fopen(state, "wx");
    CHECK(f != NULL);
    CHECK(fputs("fixture state\n", f) >= 0 && fclose(f) == 0);
    return true;
}
int main(int argc, char **argv)
{
    CHECK(argc == 3);
    fixture_root = argv[1];
    refuse = strcmp(argv[2], "refuse") == 0;
    char *args[] = {"speedrun", "fixture-peer", NULL};
    int rc = speedrun_main(2, args);
    CHECK(rc == (refuse ? 1 : 0));
    CHECK(boot_calls == (refuse ? 0u : 1u));
    CHECK(clock_reads == (refuse ? 0u : 2u));
    return 0;
}
C
includes=()
while IFS= read -r dir; do includes+=("-I$root/$dir"); done < <(
    git -C "$root" ls-files '*/*.h' | sed -n 's@/include/.*@/include@p' | sort -u
)
flags=(-std=c23 -D_DEFAULT_SOURCE -O2 -Wall -Wextra -Werror)
"${CC:-cc}" "${flags[@]}" "${includes[@]}" "$scratch/fixture.c" -o "$scratch/fixture"
mkdir "$scratch/runs"
"$scratch/fixture" "$scratch/runs" fresh > "$scratch/first"
echo 'PASS: first trial boots from empty state'
"$scratch/fixture" "$scratch/runs" fresh > "$scratch/second"
[[ $(find "$scratch/runs" -type f -name prior-trial | wc -l) == 2 ]]
[[ $(find "$scratch/runs" -mindepth 1 -maxdepth 1 -type d ! -perm 700 | wc -l) == 0 ]]
echo 'PASS: two trials with identical PID each boot from empty, private state'
"$scratch/fixture" "$scratch/runs" refuse > "$scratch/refused" 2> "$scratch/error"
grep -Fq 'create fresh startup datadir' "$scratch/error"
if grep -Eq 'STARTUP RESULT|Startup attempt:' "$scratch/refused"; then
    echo 'FAIL: directory refusal published a startup measurement' >&2
    exit 1
fi
echo 'PASS: directory refusal starts neither boot nor clock'
if (( analyze )); then
    "${CC:-cc}" "${flags[@]}" -fanalyzer "${includes[@]}" \
        -c "$scratch/fixture.c" -o "$scratch/analyzed.o"
    echo 'PASS: GCC static analysis'
fi
