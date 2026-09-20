#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise replay admission without systemd, a node, network, or datadir.
# Usage: bash tools/scripts/replay_canary_guard_selftest.sh [guard-script]
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
guard=${1:-$script_dir/replay_canary_guard.sh}
fixture=$(mktemp -d "${TMPDIR:-/tmp}/zcl-replay-guard.XXXXXX")
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$fixture/bin" "$fixture/scripts"
cp "$guard" "$fixture/scripts/replay_canary_guard.sh"
export GUARD_FIXTURE=$fixture
cat > "$fixture/bin/systemctl" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" > "$GUARD_FIXTURE/query-args"
printf '%s' "$QUERY_OUTPUT"
exit "$QUERY_STATUS"
SH
cat > "$fixture/bin/logger" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$fixture/scripts/replay_canary.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$GUARD_FIXTURE/replay-args"
exit "$REPLAY_STATUS"
SH
chmod +x "$fixture/bin/systemctl" "$fixture/bin/logger" "$fixture/scripts/replay_canary.sh"
export PATH="$fixture/bin:$PATH"
export QUERY_OUTPUT='' QUERY_STATUS=0 REPLAY_STATUS=0
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
run_guard() {
    rm -f "$fixture/replay-args"
    result=0
    PATH="${GUARD_PATH:-$PATH}" bash "$fixture/scripts/replay_canary_guard.sh" --from=genesis 'arg with spaces' \
        > "$fixture/stdout" 2> "$fixture/stderr" || result=$?
}
assert_skip() {
    [[ $result == 0 ]] || fail "skip returned $result"
    [[ ! -e $fixture/replay-args ]] || fail 'query unavailable/occupied but replay launched'
    grep -Fq "SKIP reason=$1" "$fixture/stderr" || fail "missing skip reason $1"
}
# A successful empty query allows exactly one replay and preserves argv/status.
REPLAY_STATUS=37
run_guard
[[ $result == 37 ]] || fail 'replay exit status lost'
printf '%s\n' --from=genesis 'arg with spaces' > "$fixture/expected-args"
cmp "$fixture/expected-args" "$fixture/replay-args" || fail 'replay argv changed'
printf '%s\n' --user list-units --type=service --state=active --no-legend '*mint*' \
    > "$fixture/expected-query"
cmp "$fixture/expected-query" "$fixture/query-args" || fail 'query scope changed'
REPLAY_STATUS=0
QUERY_OUTPUT=$'zclassic23-anchor-mint.service loaded active running mint\n'
run_guard
assert_skip 'mint_unit_active: zclassic23-anchor-mint.service'
# D-Bus failure with empty or partial stdout cannot establish idle capacity.
for QUERY_STATUS in 1 3 127; do
    for QUERY_OUTPUT in '' 'partial output'; do
        run_guard
        assert_skip 'mint_query_failed'
    done
done
# Preserve the existing unavailable-tool refusal without invoking host tools.
mkdir "$fixture/no-systemctl"
ln -s "$(command -v bash)" "$fixture/no-systemctl/bash"
ln -s "$(command -v dirname)" "$fixture/no-systemctl/dirname"
ln -s "$fixture/bin/logger" "$fixture/no-systemctl/logger"
GUARD_PATH=$fixture/no-systemctl
run_guard
assert_skip 'no_systemctl'
printf 'PASS: empty-success admission, argv/status, active-mint refusal, missing tool, 6 failed-query refusals; failed-query replay launches=0\n'
