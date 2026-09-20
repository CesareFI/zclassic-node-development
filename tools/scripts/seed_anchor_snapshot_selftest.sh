#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Isolated bootstrap-copy regression; no node, wallet, or operator datadir.
# Usage: bash tools/scripts/seed_anchor_snapshot_selftest.sh [script] [MiB]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${1:-$ROOT/tools/seed_anchor_snapshot.sh}"
MIB="${2:-1}"
case "$MIB" in ''|*[!0-9]*|0) echo 'MiB must be positive' >&2; exit 2 ;; esac
TMP="$(mktemp -d "${TMPDIR:-/tmp}/zcl-anchor-stage.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/datadir"
export REAL_STAT="$(command -v stat)" REAL_CP="$(command -v cp)"
export COPY_TRACE="$TMP/copies" STAT_STYLE=gnu
# Translate a qualified BSD invocation into the host's native stat for the
# fixture. GNU-style options are rejected when emulating BSD.
cat > "$TMP/bin/stat" <<'SH'
#!/usr/bin/env bash
case "$STAT_STYLE:$1:$2" in
    gnu:-c:%s|bsd:-f:%z)
        shift 2
        "$REAL_STAT" -c %s "$@" 2>/dev/null || "$REAL_STAT" -f %z "$@"
        ;;
    *) exit 1 ;;
esac
SH
cat > "$TMP/bin/cp" <<'SH'
#!/usr/bin/env bash
printf 'copy\n' >> "$COPY_TRACE"
exec "$REAL_CP" "$@"
SH
chmod +x "$TMP/bin/stat" "$TMP/bin/cp"
export PATH="$TMP/bin:$PATH"
dd if=/dev/zero of="$TMP/source" bs=1048576 count="$MIB" 2>/dev/null
"$REAL_CP" "$TMP/source" "$TMP/datadir/utxo-anchor.snapshot"

run_case() {
    local name="$1" expected="$2" copies=0 line
    : > "$COPY_TRACE"
    ZCL_DATADIR="$TMP/datadir" ZCL_ANCHOR_SNAPSHOT_SRC="$TMP/source" \
        bash "$SOURCE" > "$TMP/output"
    while IFS= read -r line; do copies=$((copies + 1)); done < "$COPY_TRACE"
    printf '%s: copy_attempts=%d expected=%d\n' "$name" "$copies" "$expected"
    if [[ "$copies" != "$expected" ]]; then
        echo "FAIL: unexpected copy count for $name" >&2
        return 1
    fi
}

run_case gnu_same_size 0
STAT_STYLE=bsd
run_case bsd_same_size 0
cmp "$TMP/source" "$TMP/datadir/utxo-anchor.snapshot"
printf 'avoided_recopy_bytes=%d\n' "$((MIB * 1048576))"

printf x >> "$TMP/source"
run_case bsd_changed_size 1
cmp "$TMP/source" "$TMP/datadir/utxo-anchor.snapshot"
rm "$TMP/datadir/utxo-anchor.snapshot"
run_case bsd_missing_target 1
cmp "$TMP/source" "$TMP/datadir/utxo-anchor.snapshot"
STAT_STYLE=unavailable
run_case unknown_size_still_copies 1
cmp "$TMP/source" "$TMP/datadir/utxo-anchor.snapshot"
STAT_STYLE=bsd
: > "$TMP/source"
: > "$TMP/datadir/utxo-anchor.snapshot"
run_case empty_size_still_copies 1
rm "$TMP/source"
run_case missing_source_skips 0
printf x > "$TMP/source"
rm -r "$TMP/datadir"
run_case missing_datadir_skips 0
echo 'seed-anchor-snapshot selftest: PASS'
