#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Quiet-startup log observer cost and invalidation; never launches a node.
set -euo pipefail
export LC_ALL=C
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
bench=0
if [[ ${1:-} == --bench ]]; then bench=1; shift; fi
subject=${1:-$root/tools/scripts/cold_start_to_tip_stopwatch.sh}
. "$root/tools/scripts/stopwatch_json_lib.sh"
scratch=$(mktemp -d /tmp/zcl-park-cache.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
sed -n '/^log_named_park() {/,/^}/p' "$subject" > "$scratch/reader.sh"
. "$scratch/reader.sh"
DATADIR=$scratch
cache_supported=1
metadata=$(stopwatch_file_metadata "$scratch/reader.sh") || metadata=' unavailable'
case "$metadata" in *' unavailable') cache_supported=0 ;; esac
grep() {
    printf 'scan\n' >> "$scratch/scans"
    local rc=0
    command grep "$@" || rc=$?
    if [[ -n ${append_after_scan:-} ]]; then
        printf '%s\n' "$append_after_scan" >> "$DATADIR/node.log"
    fi
    return "$rc"
}
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check() {
    local expected=$1 status=$2 actual=stale rc=0
    log_named_park actual || rc=$?
    [[ $actual == "$expected" && $rc == "$status" ]] ||
        fail "expected <$expected> rc=$status; got <$actual> rc=$rc"
}
if [[ $bench == 1 ]]; then
    awk 'BEGIN { for (i=0; i<131072; i++) printf "%0127d\n", i }' > "$DATADIR/node.log"
    : > "$scratch/scans"
    TIMEFORMAT='100 quiet-log polls: %3R s wall, %3U s user, %3S s system'
    time for ((i=0; i<100; i++)); do check '' 1; done
    printf 'log_bytes=%s scans=%s\n' "$(wc -c < "$DATADIR/node.log")" "$(wc -l < "$scratch/scans")"
    exit 0
fi

check '' 2
printf 'ordinary boot progress\n' > "$DATADIR/node.log"
: > "$scratch/scans"
check '' 1
check '' 1
expected_scans=$((2 - cache_supported))
[[ $(wc -l < "$scratch/scans") == "$expected_scans" ]] || fail 'unchanged miss scan budget'
printf "PARKED alive-degraded at gate 'first'\n" >> "$DATADIR/node.log"
check first 0
check first 0
expected_scans=$((2 * expected_scans))
[[ $(wc -l < "$scratch/scans") == "$expected_scans" ]] || fail 'unchanged hit scan budget'
printf "PARKED alive-degraded at gate 'final'\n" > "$DATADIR/node.log"
check final 0
# Same-size rewrite, restoring mtime: ctime must invalidate the cached hit.
cp -p "$DATADIR/node.log" "$scratch/stamp"
printf "PARKED alive-degraded at gate 'other'\n" > "$DATADIR/node.log"
touch -r "$scratch/stamp" "$DATADIR/node.log"
check other 0
cp -p "$scratch/stamp" "$scratch/replacement"
mv "$scratch/replacement" "$DATADIR/node.log"
check final 0
: > "$DATADIR/node.log"
check '' 1
rm "$DATADIR/node.log"
check '' 2
# An append racing the completed scan must remain visible on the next poll.
printf 'ordinary boot progress\n' > "$DATADIR/node.log"
append_after_scan="PARKED alive-degraded at gate 'racing'"
check '' 1
append_after_scan=''
check racing 0
printf "PARKED alive-degraded at gate 'again'\n" > "$DATADIR/node.log"
check again 0
# A symlink stamp describes the link, not its changing target. Do not cache it.
mv "$DATADIR/node.log" "$scratch/target"
ln -s "$scratch/target" "$DATADIR/node.log"
check again 0
printf "PARKED alive-degraded at gate 'linked'\n" > "$scratch/target"
check linked 0
rm "$DATADIR/node.log"
mv "$scratch/target" "$DATADIR/node.log"
# Unavailable metadata must fall back to scanning, never stale evidence.
stat() { return 1; }
: > "$scratch/scans"
check linked 0
check linked 0
[[ $(wc -l < "$scratch/scans") == 2 ]] || fail 'metadata failure reused cache'
printf "PARKED alive-degraded at gate 'fresh'\n" > "$DATADIR/node.log"
check fresh 0
unset -f stat
# A scan error with a valid stamp cannot become a cached miss.
unset LOG_PARK_SIGNATURE
grep() { return 2; }
check '' 2
unset -f grep
check fresh 0
# A different datadir must never inherit the previous log's result.
mkdir "$scratch/next"
DATADIR=$scratch/next
printf 'ordinary boot progress\n' > "$DATADIR/node.log"
check '' 1
[[ $cache_supported == 1 ]] || echo 'SKIP: precise GNU stat cache unavailable; fallback exercised'
echo 'stopwatch park cache: PASS (reuse, mutation, replacement, symlink and errors)'
