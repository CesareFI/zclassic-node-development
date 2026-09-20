#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Qualify topology output and bound startup reads. No node or datadir is used.
# Usage: bash tools/scripts/serial_bench_topology_selftest.sh [--bench] [source.c]
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mode=test
if [[ ${1:-} == --bench ]]; then mode=bench; shift; fi
source_file="${1:-$root/tools/serial_bench.c}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/serial-bench-topology.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Compile the actual topology code, keeping the standalone benchmark's large
# parser/link dependencies out of this sysfs-only test.
awk '/^struct cpu_topo / { copy = 1 }
     /^static bool pin_to_cpu/ { copy = 0 }
     copy { print }' "$source_file" > "$tmp/topology.inc"
cat > "$tmp/test.c" <<'EOF'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#define CHECK(e) do { if (!(e)) { \
    fprintf(stderr, "topology: FAIL line %d: %s\n", __LINE__, #e); exit(1); \
} } while (0)
static int domains[64], reads, size_missing;
static long configured = 64;
static long fixture_sysconf(int name)
{
    CHECK(name == _SC_NPROCESSORS_CONF);
    return configured;
}
static FILE *fixture_fopen(const char *path, const char *mode)
{
    int cpu = -1, offset = 0;
    CHECK(strcmp(mode, "r") == 0);
    CHECK(sscanf(path, "/sys/devices/system/cpu/cpu%d/cache/index3/%n",
                 &cpu, &offset) == 1);
    CHECK(offset > 0 && cpu >= 0 && cpu < 64);
    bool size = strcmp(path + offset, "size") == 0;
    CHECK(size || strcmp(path + offset, "shared_cpu_list") == 0);
    reads++;
    if (domains[cpu] < 0 || (size && size_missing)) return NULL;
    FILE *f = tmpfile();
    CHECK(f != NULL);
    if (size) CHECK(fputs("32768K\n", f) >= 0);
    else CHECK(fprintf(f, "%d\n", domains[cpu]) > 0);
    rewind(f);
    return f;
}
#define fopen fixture_fopen
#define sysconf fixture_sysconf
#include "topology.inc"
#undef fopen
#undef sysconf

static void probe(int cpu, int domain, int first, bool known)
{
    struct cpu_topo t;
    reads = 0;
    topo_probe(cpu, &t);
    CHECK(t.cpu == cpu && t.known == known && t.ccd_index == domain);
    if (domains[cpu] >= 0) {
        char expected[128];
        CHECK(snprintf(expected, sizeof(expected), "%d", domains[cpu]) > 0);
        CHECK(strcmp(t.l3_shared, expected) == 0);
        CHECK(t.l3_kb == (size_missing ? 0 : 32768));
    } else CHECK(t.l3_shared[0] == '\0' && t.l3_kb == 0);
    int limit = first + 3; /* selected list, size, scan through first match */
    if (reads != limit) {
        fprintf(stderr, "topology: cpu=%d reads=%d expected=%d\n", cpu, reads, limit);
        exit(1);
    }
}
int main(void)
{
    /* Repeated domains and a missing/offline CPU do not renumber later CCDs. */
    for (int i = 0; i < 64; i++) domains[i] = 2;
    domains[0] = domains[1] = domains[4] = 8;
    domains[2] = -1;
    domains[6] = 9;
    domains[63] = 12;
    for (int i = 0; i < 64; i++) {
        if (i == 2) probe(i, -1, -2, false);
        else if (domains[i] == 8) probe(i, 0, 0, true);
        else if (domains[i] == 2) probe(i, 1, 3, true);
        else if (domains[i] == 9) probe(i, 2, 6, true);
        else probe(i, 3, 63, true);
    }
    size_missing = 1;
    probe(4, 0, 0, true);
    size_missing = 0;
    configured = -1;
    probe(0, -1, -1, false);
    configured = 64;
    for (int i = 0; i < 64; i++) domains[i] = i;
    probe(15, 15, 15, true);
    probe(16, -1, 15, false); /* preserve the existing 16-domain bound */
    puts("serial-bench-topology: PASS (output, sparse CPUs, bounds, early exit)");
    return 0;
}
EOF
cat > "$tmp/bench.c" <<'EOF'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
static unsigned long opens;
static FILE *counted_fopen(const char *path, const char *mode)
{
    opens++;
    return fopen(path, mode);
}
#define fopen counted_fopen
#include "topology.inc"
#undef fopen
int main(void)
{
    struct cpu_topo t;
    struct timespec begin, end;
    if (clock_gettime(CLOCK_MONOTONIC, &begin) != 0) return 1;
    for (int i = 0; i < 2000; i++) topo_probe(0, &t);
    if (clock_gettime(CLOCK_MONOTONIC, &end) != 0) return 1;
    printf("2000 cpu0 topology probes: %lu opens, %.6f s; known=%d ccd=%d L3=%ldK cpus=%s\n",
           opens, (double)(end.tv_sec - begin.tv_sec) +
           (double)(end.tv_nsec - begin.tv_nsec) / 1e9,
           t.known, t.ccd_index, t.l3_kb, t.l3_shared);
    return 0;
}
EOF
"${CC:-cc}" -std=c23 -O2 -Wall -Wextra -Werror -pedantic \
    -D_POSIX_C_SOURCE=200809L "$tmp/$mode.c" -o "$tmp/run"
"$tmp/run"
