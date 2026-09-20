#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise bundle delivery and flush scope using only isolated, inert fixtures.
set -euo pipefail

root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
courier=${1:-"$root/platform/deploy/zclassic23-bundle-bootstrap.sh"}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/zcl-bundle-flush.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"
export FLUSH_LOG="$scratch/flush.log"
export REAL_CP
REAL_CP=$(command -v cp)
command -v openssl >/dev/null || { echo 'FAIL: openssl required' >&2; exit 1; }

cat > "$scratch/bin/sync" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s' "$#" >> "$FLUSH_LOG"
for arg in "$@"; do printf ' <%s>' "$arg" >> "$FLUSH_LOG"; done
printf '\n' >> "$FLUSH_LOG"
case "${FLUSH_MODE:-supported}:$#" in
    unsupported:2|failed:*) exit 1 ;;
esac
SH
cat > "$scratch/bin/cp" <<'SH'
#!/usr/bin/env bash
set -eu
"$REAL_CP" "$@"
if [[ ${CORRUPT_COPY:-0} == 1 ]]; then
    printf 'corruption\n' >> "${@: -1}"
fi
SH
cat > "$scratch/sha3" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
openssl dgst -sha3-256 "$1" | awk '{print $NF}'
SH
chmod +x "$scratch/bin/sync" "$scratch/bin/cp" "$scratch/sha3"
export PATH="$scratch/bin:$PATH"
source_bundle="$scratch/consensus-state-bundle-fixture.sqlite"
printf 'inert delivery fixture, not a consensus bundle\n' > "$source_bundle"

fail() { printf 'bundle-bootstrap-flush: FAIL: %s\n' "$*" >&2; exit 1; }
run_courier() {
    bash "$courier" --source="$source_bundle" --datadir="$datadir" \
        --sha3-tool="$scratch/sha3" > "$scratch/courier.log" 2>&1
}
check_delivery() {
    cmp "$source_bundle" "$destination" || fail 'delivered bytes changed'
    [[ $(LC_ALL=C ls -ld "$destination") == -r--r--r--* ]] ||
        fail 'staged file must be read-only'
    [[ -z $(find "$datadir" -name '*.tmp.*' -print) ]] ||
        fail 'temporary copy remains'
}

# Nested new parents must be covered by the filesystem-wide durability scope.
# Spaces in the pathname must remain one sync argument.
datadir="$scratch/new parents/child/node"
destination="$datadir/bundles/${source_bundle##*/}"
run_courier
check_delivery
expected="2 <-f> <$datadir/bundles>"
[[ $(<"$FLUSH_LOG") == "$expected" ]] || fail 'expected one filesystem flush'

# Unsupported targeted flushes and I/O errors retain the original best-effort
# global fallback. No failure is promoted to a new validation claim.
for mode in unsupported failed; do
    datadir="$scratch/$mode"
    destination="$datadir/bundles/${source_bundle##*/}"
    : > "$FLUSH_LOG"
    FLUSH_MODE=$mode run_courier
    check_delivery
    expected=$(printf '2 <-f> <%s/bundles>\n0' "$datadir")
    [[ $(<"$FLUSH_LOG") == "$expected" ]] || fail "$mode fallback changed"
done

# Already staged or installed state must not trigger copy, hashing, or flush.
: > "$FLUSH_LOG"
saved_source=$source_bundle
source_bundle="$scratch/absent.sqlite"
CORRUPT_COPY=1 run_courier
source_bundle=$saved_source
check_delivery
[[ ! -s "$FLUSH_LOG" ]] || fail 'already-staged run flushed storage'
datadir="$scratch/installed"
mkdir -p "$datadir"
touch "$datadir/consensus-bundle-installed.marker"
source_bundle="$scratch/absent.sqlite"
CORRUPT_COPY=1 run_courier
source_bundle=$saved_source
[[ ! -e "$datadir/bundles" && ! -s "$FLUSH_LOG" ]] ||
    fail 'already-installed run staged or flushed'

# Corruption must be refused before rename/flush, and the temp copy removed.
datadir="$scratch/corrupt"
if CORRUPT_COPY=1 run_courier; then fail 'corrupt copy accepted'; fi
grep -q 'copy digest mismatch' "$scratch/courier.log" || fail 'wrong refusal'
[[ -z $(find "$datadir/bundles" -type f -print) && ! -s "$FLUSH_LOG" ]] ||
    fail 'corrupt copy published, retained, or flushed'

printf 'bundle-bootstrap-flush-selftest: PASS (delivery, flush scope, fallbacks, guards, corruption)\n'
