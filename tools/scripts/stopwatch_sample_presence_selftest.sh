#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic row-presence regression; --bench measures observer cost only.
set -euo pipefail
export LC_ALL=C
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
case "${1:-}" in
    ''|--bench) ;;
    *) echo "usage: $0 [--bench]" >&2; exit 2 ;;
esac
scratch=$(mktemp -d "${TMPDIR:-/tmp}/zcl-sample-presence.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
sed -n '/^samples_have_data() {/,/^}/p' \
    "$root/tools/scripts/stopwatch_artifact_symmetry_check.sh" > "$scratch/reader.sh"
. "$scratch/reader.sh"
declare -F samples_have_data >/dev/null || { echo 'FAIL: reader missing' >&2; exit 1; }

# Original row-count predicate, retained as a behavioral and timing reference.
reference_samples_have_data() {
    [ "$(awk 'NR>1' "$1" 2>/dev/null | wc -l)" -gt 0 ] 2>/dev/null
}
check() {
    local label=$1 expected=$2 actual=0 reference=0
    samples_have_data "$scratch/samples.tsv" || actual=1
    reference_samples_have_data "$scratch/samples.tsv" || reference=1
    if [[ $actual != "$expected" || $actual != "$reference" ]]; then
        printf 'FAIL: %s expected=%s actual=%s reference=%s\n' \
            "$label" "$expected" "$actual" "$reference" >&2
        exit 1
    fi
}
check missing 1
: > "$scratch/samples.tsv"
check empty 1
printf 'header' > "$scratch/samples.tsv"
check unterminated-header 1
printf 'header\n' > "$scratch/samples.tsv"
check header-only 1
printf 'header\n0\t1\t3000000\n' > "$scratch/samples.tsv"
check one-row 0
printf 'header\n0\t1\t3000000' > "$scratch/samples.tsv"
check unterminated-row 0
printf 'header\n\n' > "$scratch/samples.tsv"
check blank-row 0
printf 'header\r\n0\t1\t3000000\r\n' > "$scratch/samples.tsv"
check crlf 0

# Observe records processed by the real awk program. Read-ahead buffering is
# allowed, but processing records after the second is unnecessary. Unlike an
# open FIFO, this guard does not depend on the awk implementation's buffering.
printf 'header\n0\t1\t3000000\n1\t2\t3000001\n' > "$scratch/samples.tsv"
awk() {
    local program=$1
    shift
    command awk -v overread="$scratch/overread" '
        NR > 2 { print NR > overread }
    '"$program" "$@"
}
samples_have_data "$scratch/samples.tsv"
unset -f awk
if [[ -e $scratch/overread ]]; then
    echo 'FAIL: reader processed records after observing a data row' >&2
    exit 1
fi
echo 'sample-presence: PASS (8 file cases and bounded record processing)'

if [[ ${1:-} == --bench ]]; then
    awk 'BEGIN {
        print "t_s\tunix_s\thstar"
        for (i = 0; i < 1000000; i++)
            printf "%d\t%d\t%d\n", i, 1700000000+i, 3000000+i
    }' > "$scratch/samples.tsv"
    check million-rows 0
    wc -c < "$scratch/samples.tsv"
    TIMEFORMAT='reference 10 checks: %3R s wall, %3U s user, %3S s system'
    time for ((i=0; i<10; i++)); do reference_samples_have_data "$scratch/samples.tsv"; done
    TIMEFORMAT='changed 10 checks: %3R s wall, %3U s user, %3S s system'
    time for ((i=0; i<10; i++)); do samples_have_data "$scratch/samples.tsv"; done
fi
