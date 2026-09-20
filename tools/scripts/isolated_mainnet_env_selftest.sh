#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Mainnet-canary readiness fixtures; no node or listening socket is created.
set -euo pipefail

SELF_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
source "$SELF_DIR/isolated_mainnet_env.sh"
[ -x "$ISO_JSONQ_BIN" ] || iso_die 'mainnet readiness selftest requires make jsonq'

fixture="$(mktemp -d "${TMPDIR:-/tmp}/z23-mainnet-readiness.XXXXXX")"
trap 'rm -rf -- "$fixture"' EXIT
ISO_DD="$fixture"
ISO_NODE_PID=""
touch "$fixture/.cookie"

fixture_reply=""
fixture_rpc_rc=0
iso_rpc() { printf '%s\n' "$fixture_reply"; return "$fixture_rpc_rc"; }
fail() {
    printf 'isolated-mainnet-readiness selftest: FAIL: %s\n' "$*" >&2
    exit 1
}

for fixture_reply in \
    '{"result":null,"error":{"code":-28,"message":"warming up"},"id":123}' \
    '{"result":0,"error":{"code":-28},"id":1}' \
    '{"result":"0","error":null}' \
    '{"result":0,"error":"null"}' \
    '{"result":0}' \
    '{"result":-1,"error":null}' \
    '{"result":1.5,"error":null}' \
    '{"result":1e2,"error":null}' \
    '{"result":true,"error":null}' \
    '{"result":[],"error":null}' \
    '{"result":0,"error":null} trailing' \
    '0' ''; do
    if iso_rpc_nonnegative_result getblockcount >/dev/null; then
        fail "invalid response accepted: $fixture_reply"
    fi
done

fixture_reply='{"result":0,"error":null,"id":1}'
[ "$(iso_rpc_nonnegative_result getblockcount)" = 0 ] || fail 'height zero refused'
iso_wait_rpc_ready 1 || fail 'successful height zero did not become ready'

fixture_rpc_rc=1
if iso_rpc_nonnegative_result getblockcount >/dev/null; then
    fail 'failed RPC transport qualified through successful-looking output'
fi

fixture_rpc_rc=0
fixture_reply='{"result":null,"error":{"code":-28},"id":123}'
if iso_wait_rpc_ready 1; then fail 'RPC error became ready'; fi

printf 'isolated-mainnet-readiness selftest: PASS typed_rpc=true errors_refused=true\n'
