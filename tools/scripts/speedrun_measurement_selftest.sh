#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise the real speedrun entry point with a deterministic boot boundary.
# No node, network, wallet, datadir or production service is opened.
set -euo pipefail
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
source_file=${1:-$root/tools/speedrun.c}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/zcl-speedrun-measurement.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/fixture.c" <<'C'
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#define CHECK(expr) do { if (!(expr)) { \
    fprintf(stderr, "speedrun fixture: failed: %s\n", #expr); exit(1); \
} } while (0)
static char *fixture_mkdtemp(char *path);
#define mkdtemp fixture_mkdtemp
#define main speedrun_main
C
printf '#include "%s"\n' "$source_file" >> "$scratch/fixture.c"
cat >> "$scratch/fixture.c" <<'C'
#undef main
#undef mkdtemp
static bool boot_ok;
static unsigned clock_reads, boot_calls;
static char *fixture_mkdtemp(char *path)
{
    CHECK(strcmp(path, "/tmp/zcl23-speedrun-XXXXXX") == 0);
    memcpy(path + sizeof("/tmp/zcl23-speedrun-") - 1, "trial1", 6);
    return path;
}
int64_t clock_now_monotonic_ns(void)
{
    /* Exactly 2345 ms spent in boot; no tip or validation observation. */
    CHECK(clock_reads < 2);
    return clock_reads++ == 0 ? 10000000000LL : 12345000000LL;
}
void app_context_defaults(struct app_context *ctx)
{
    memset(ctx, 0, sizeof(*ctx));
}
bool app_init(struct app_context *ctx)
{
    CHECK(clock_reads == 1);
    CHECK(strcmp(ctx->file_service_peer, "fixture-peer") == 0);
    CHECK(!ctx->listen && !ctx->tor);
    CHECK(ctx->p2p_port == 18044 && ctx->rpc_port == 18245);
    CHECK(ctx->datadir != NULL);
    boot_calls++;
    puts("fixture: catch-up and sovereign validation have not completed");
    return boot_ok;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    boot_ok = strcmp(argv[1], "boot-ok") == 0;
    char *args[] = {"speedrun", "fixture-peer", NULL};
    int rc = speedrun_main(2, args);
    CHECK(clock_reads == 2 && boot_calls == 1);
    CHECK(rc == (boot_ok ? 0 : 1));
    return rc;
}
C
includes=()
while IFS= read -r dir; do includes+=("-I$root/$dir"); done < <(
    git -C "$root" ls-files '*/*.h' |
        sed -n 's@/include/.*@/include@p' | sort -u
)
"${CC:-cc}" -std=c23 -D_DEFAULT_SOURCE -O2 -Wall -Wextra -Werror \
    "${includes[@]}" "$scratch/fixture.c" -o "$scratch/fixture"
fail() { echo "speedrun measurement: FAIL: $*" >&2; exit 1; }
"$scratch/fixture" boot-ok > "$scratch/ok"
if "$scratch/fixture" boot-failed > "$scratch/failed"; then
    fail "failed boot returned success"
else
    rc=$?
    [[ $rc == 1 ]] || fail "unexpected failed boot status $rc"
fi
for result in ok failed; do
    cat "$scratch/$result"
    grep -Eq 'Startup attempt: +2345ms' "$scratch/$result" || fail "startup duration absent"
    grep -Fq 'Time to tip: NOT MEASURED' "$scratch/$result" || fail "tip claimed without observation"
    grep -Fq 'Sovereign validation: NOT MEASURED' "$scratch/$result" || fail "validation claimed without observation"
    if grep -Eq 'zero to tip|SUCCESS' "$scratch/$result"; then
        fail "startup promoted to sync success"
    fi
done
grep -Fq 'Startup status: COMPLETE' "$scratch/ok" || fail "successful startup missing"
grep -Fq 'Startup status: FAILED' "$scratch/failed" || fail "failed startup missing"
echo 'speedrun measurement: PASS (2345 ms startup, sync remains unmeasured)'
