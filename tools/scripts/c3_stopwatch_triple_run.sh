#!/usr/bin/env bash
# c3_stopwatch_triple_run.sh — run the C3 wipe-to-tip stopwatch N times against
# ONE explicitly-named serving fixture peer and emit a per-run comparison table.
#
# WHY THIS EXISTS, GIVEN cold_start_to_tip_stopwatch.sh ALREADY MEASURES A RUN.
#
# The single-run harness answers "did H* reach network_tip inside the budget".
# network_tip is a HEIGHT the peer advertised over the wire. Two things it
# cannot answer on its own, and this driver adds exactly those two:
#
#   1. HASH IDENTITY, not just height equality. "H* == network_tip" proves the
#      client counted to the same number as the peer, not that it agrees on
#      which chain that number names. This driver reads the peer's own
#      `core chain tip` (height AND hash) immediately before and after each run,
#      and polls the CLIENT's `core chain tip` while it runs, so the verdict line
#      can state client_tip_hash == peer_tip_hash at the same height, or say
#      plainly that it could not. The client's scratch datadir is deleted by the
#      harness on the way out, so the hash has to be sampled DURING the run —
#      there is no after-the-fact way to recover it.
#
#   2. REPEATABILITY. One run is an anecdote; the 600s bar is a claim about the
#      thing in general. N genuinely-wiped runs back to back, each against a
#      peer whose tip is recorded at both ends of the window, is the smallest
#      honest form of that claim.
#
# It does NOT re-implement any measurement. Wall clock, boots, per-phase
# durations, CPU, RSS, disk read/write and block-body payload bytes all come
# from the single-run harness's own proof.json + samples.tsv, which this driver
# copies a pointer to and quotes. Nothing here computes a duration.
#
# The peer is a REQUIRED, explicitly-named argument for the same reason the
# single-run harness made it required: a proof lane that inherits its peer is
# not a proof. With no --peer this driver exits 2 and names the flag.
#
# ISOLATION. This driver never writes to the peer's datadir: it reads the peer
# tip through the peer's OWN RPC port, which is a read of the running process,
# and it never touches the peer's systemd unit. The client side is entirely the
# single-run harness's business (fresh mktemp /tmp datadir, ports 39170-39173,
# isolated $HOME, no bundle/snapshot/import flags).
#
# USAGE
#   tools/scripts/c3_stopwatch_triple_run.sh --peer=127.0.0.1:39070 \
#       [--peer-datadir=DIR] [--peer-rpcport=N] [--runs=3] [--bin=PATH] \
#       [--budget=600] [--out=DIR]
#   tools/scripts/c3_stopwatch_triple_run.sh --selftest
#   ZCL_CS_ROOT selects an existing private scratch parent, as for the single
#   stopwatch. Each run gets its own child directory for client discovery.
#
# EXIT
#   0  every run PASSed the height bar AND the hash check agreed (or was
#      honestly reported unavailable — see hash_verdict in the ledger).
#   1  at least one run did not PASS. The table says which, with that run's own
#      verdict and named blocker.
#   2  prerequisite absent (no --peer, no binary, peer RPC unreadable).
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

PEER=""
# Bundle/file-service peer. Optional, no default, and NAMEABLE on the command
# line on purpose: without --file-peer this driver could still pick one up by
# inheriting ZCL_CS_FILE_PEER from the environment, which is an implicit peer —
# exactly what --peer refuses to allow. Stating it here puts it in the printed
# header and in every runs.jsonl line, so a ledger row records which lane it
# measured. With NO file peer the node has no state source: it reports the named
# blocker bootstrap.no_state_source and does a from-genesis IBD instead of the
# bundle-then-fold path (measured 2026-07-30: H* pinned at 0 for the whole 600 s).
FILE_PEER="${ZCL_CS_FILE_PEER:-}"
PEER_DATADIR="${ZCL_CS_PEER_DATADIR:-$HOME/.zclassic-c23-fixture-serve}"
PEER_RPCPORT="${ZCL_CS_PEER_RPCPORT:-39071}"
RUNS=3
NODE_BIN="${ZCL_CS_NODE_BIN:-$REPO_ROOT/build/bin/z23}"
BUDGET="${ZCL_CS_BUDGET_SECS:-600}"
OUT_DIR=""
SELFTEST=0
# Client RPC port the single-run harness uses (P2P=39170 RPC=39171 FS=39172
# HTTPS=39173). Kept as a variable so a reader can see it is a copy of that
# harness's constant, not an independent choice.
CLIENT_RPCPORT=39171
CS_ROOT="${ZCL_CS_ROOT:-$HOME/.local/state/zclassic23/scratch/coldstart}"

for arg in "$@"; do
    case "$arg" in
        --peer=*)         PEER="${arg#--peer=}" ;;
        --file-peer=*)    FILE_PEER="${arg#--file-peer=}" ;;
        --peer-datadir=*) PEER_DATADIR="${arg#--peer-datadir=}" ;;
        --peer-rpcport=*) PEER_RPCPORT="${arg#--peer-rpcport=}" ;;
        --runs=*)         RUNS="${arg#--runs=}" ;;
        --bin=*)          NODE_BIN="${arg#--bin=}" ;;
        --budget=*)       BUDGET="${arg#--budget=}" ;;
        --out=*)          OUT_DIR="${arg#--out=}" ;;
        --selftest)       SELFTEST=1 ;;
        *) echo "c3-stopwatch-triple: unknown flag: $arg" >&2; exit 2 ;;
    esac
done

# ── json_field <json> <key> — first "key":<scalar> in a flat-ish JSON blob.
# Deliberately dumb: proof.json is emitted by printf one key per line, and the
# tip doc is a single line with unique keys. A dependency-free reader is the
# point; anything that needs real parsing is quoted from the artifact instead.
json_field() {
    # All callers supply literal identifier keys and simple scalar values.
    # Keep this hot polling path inside bash: three external tools per field
    # add observer CPU/process load while the client is doing IBD. As before,
    # this is not a general JSON parser (no string escape or array decoding).
    local pattern='"'"${2}"'"[[:space:]]*:[[:space:]]*"?([^",}'$'\n'']*)'
    if [[ ${1:-} =~ $pattern ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}

# ── tip_doc <datadir> <rpcport> — one `core chain tip` line, or empty.
# Read through the RUNNING node's RPC; the datadir is only how the CLI finds the
# auth cookie.
tip_doc() {
    local dd="$1" port="$2" doc
    [ -n "$dd" ] || return 0
    # Bound TERM-resistant clients too. A failed/timed-out command may have
    # printed a plausible tip prefix; only a successful read is evidence.
    if doc="$(timeout --kill-after=1 20 "$NODE_BIN" -datadir="$dd" \
        -rpcport="$port" core chain tip 2>/dev/null)"; then
        printf '%s' "$doc"
    fi
}

# ── tip_h_hash <tip-doc> — "<height> <hash>", or "-1 -" when unreadable.
# A tip doc that says ok:false is NOT laundered into a height of 0: it reports
# the -1 never-read sentinel, so a reader can tell "peer said 0" from "nobody
# asked successfully".
tip_h_hash() {
    local doc="${1:-}" h="" hash="" key value pattern
    # Decode this sample in the caller's shell. Three command substitutions
    # per tip compete with IBD even when json_field uses only shell builtins.
    # These are the same simple scalars as json_field, not general JSON.
    for key in ok height hash; do
        value=""
        pattern='"'"$key"'"[[:space:]]*:[[:space:]]*"?([^",}'$'\n'']*)'
        if [[ $doc =~ $pattern ]]; then value=${BASH_REMATCH[1]}; fi
        case "$key" in
            ok) [ "$value" = true ] || { printf '%s' "-1 -"; return 0; } ;;
            height) h=$value ;;
            hash) hash=$value ;;
        esac
    done
    case "$h" in ''|*[!0-9]*) h="-1" ;; esac
    [ -n "$hash" ] || hash="-"
    printf '%s %s' "$h" "$hash"
}

# ── classify_exit <rc> — the single-run harness's verdict table, quoted.
# Kept as a pure function so --selftest can assert it did not drift.
classify_exit() {
    case "${1:-}" in
        0) printf 'pass' ;;
        1) printf 'fail' ;;
        2) printf 'skip' ;;
        3) printf 'seam' ;;
        4) printf 'stalled-named' ;;
        5) printf 'frontier-busy-timeout' ;;
        6) printf 'readback-failed' ;;
        *) printf 'unknown' ;;
    esac
}

# ── hash_verdict <client-h> <client-hash> <peer-h> <peer-hash>
# The whole point of this driver. "agree" is only ever returned when both sides
# produced a real 64-hex hash at the SAME height and those hashes are equal.
# Every other case names itself; none of them is allowed to read as agreement.
hash_verdict() {
    local ch="${1:-}" chash="${2:-}" ph="${3:-}" phash="${4:-}"
    if [ "$ch" = "-1" ] || [ -z "$chash" ] || [ "$chash" = "-" ]; then
        printf 'client_tip_never_read'; return 0
    fi
    if [ "$ph" = "-1" ] || [ -z "$phash" ] || [ "$phash" = "-" ]; then
        printf 'peer_tip_never_read'; return 0
    fi
    if [ "$ch" != "$ph" ]; then
        printf 'height_mismatch(client=%s,peer=%s)' "$ch" "$ph"; return 0
    fi
    if [ "$chash" = "$phash" ]; then printf 'agree'; else printf 'HASH_MISMATCH'; fi
}

# ── selftest — hermetic. No binary, no network, no datadir, no peer.
if [ "$SELFTEST" = "1" ]; then
    bash "$SCRIPT_DIR/c3_stopwatch_tip_decode_selftest.sh" || exit 1
    st_fail=0
    st_check() { # <label> <expect> <got>
        if [ "$2" = "$3" ]; then echo "  ok   $1"; else
            echo "  FAIL $1: expected [$2] got [$3]"; st_fail=1; fi
    }
    echo "c3-stopwatch-triple --selftest"
    st_check "scalar polling needs no external processes" "3196929" \
        "$(PATH=/nonexistent json_field '{"height":3196929}' height)"
    st_check "quoted scalar" "serving" \
        "$(json_field '{"phase":"serving"}' phase)"
    st_check "pretty scalar" "123" \
        "$(json_field $'{\n  "height" : 123\n}' height)"
    st_check "first duplicate field wins" "1" \
        "$(json_field '{"height":1,"height":2}' height)"
    st_check "missing field is empty" "" \
        "$(json_field '{"height":1}' missing)"
    st_check "empty string is empty" "" \
        "$(json_field '{"phase":""}' phase)"
    st_check "null remains null" "null" \
        "$(json_field '{"wall_clock_seconds":null}' wall_clock_seconds)"
    st_check "decimal duration" "12.5" \
        "$(json_field '{"wall_clock_seconds":12.5}' wall_clock_seconds)"
    st_check "negative sentinel" "-1" \
        "$(json_field '{"height":-1}' height)"
    st_check "exit 0 is pass"            "pass"          "$(classify_exit 0)"
    st_check "exit 3 is seam"            "seam"          "$(classify_exit 3)"
    st_check "exit 4 is stalled-named"   "stalled-named" "$(classify_exit 4)"
    st_check "exit 2 is skip"            "skip"          "$(classify_exit 2)"
    st_check "unmapped exit is unknown"  "unknown"       "$(classify_exit 99)"
    _a="00000c1f26f776880b5dc0e290576b0d3d7f9c9b9b0a4d237df95987ab8b42db"
    _b="00000000000000000000000000000000000000000000000000000000deadbeef"
    st_check "equal hash at equal height agrees" \
        "agree" "$(hash_verdict 100 "$_a" 100 "$_a")"
    st_check "different hash at equal height is a MISMATCH, never agreement" \
        "HASH_MISMATCH" "$(hash_verdict 100 "$_a" 100 "$_b")"
    st_check "equal hash at different height is a height mismatch" \
        "height_mismatch(client=100,peer=101)" "$(hash_verdict 100 "$_a" 101 "$_a")"
    st_check "unread client tip is named, not agreement" \
        "client_tip_never_read" "$(hash_verdict -1 "-" 100 "$_a")"
    st_check "unread peer tip is named, not agreement" \
        "peer_tip_never_read" "$(hash_verdict 100 "$_a" -1 "-")"
    st_check "an empty client hash is never agreement" \
        "client_tip_never_read" "$(hash_verdict 100 "" 100 "")"
    _ok='{"ok":true,"data":{"hash":"'"$_a"'","height":3196929,"time":1}}'
    st_check "tip doc parses to height and hash" \
        "3196929 $_a" "$(tip_h_hash "$_ok")"
    st_check "an ok:false tip doc reads as never-read, not height 0" \
        "-1 -" "$(tip_h_hash '{"ok":false,"error":{"code":"TOOL_ERROR"}}')"
    st_check "an empty tip doc reads as never-read" \
        "-1 -" "$(tip_h_hash "")"
    # The no-implicit-peer guardrail, asserted the same way the single-run
    # harness asserts its own: the flag must be required, so that a proof lane
    # cannot quietly regain a default peer between runs.
    st_check "no default peer is baked into this driver" "" "$PEER"
    bash "$SCRIPT_DIR/c3_stopwatch_scratch_selftest.sh" || st_fail=1
    bash "$SCRIPT_DIR/c3_stopwatch_tip_query_selftest.sh" || st_fail=1
    [ "$st_fail" = "0" ] && echo "c3-stopwatch-triple --selftest: ALL OK" \
        || echo "c3-stopwatch-triple --selftest: FAILED"
    exit "$st_fail"
fi

[ -n "$PEER" ] || { echo "c3-stopwatch-triple: SKIP (no peer stated; pass --peer=HOST:PORT — there is deliberately no default)"; exit 2; }
[ -x "$NODE_BIN" ] || { echo "c3-stopwatch-triple: SKIP (node binary absent/not executable: $NODE_BIN)"; exit 2; }
case "$RUNS" in ''|*[!0-9]*|0) echo "c3-stopwatch-triple: SKIP (--runs must be a positive integer, got '$RUNS')"; exit 2 ;; esac

OUT_DIR="${OUT_DIR:-$REPO_ROOT/build/c3-stopwatch/triple-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
mkdir -p "$OUT_DIR" || { echo "c3-stopwatch-triple: SKIP (cannot create $OUT_DIR)"; exit 2; }
LEDGER="$OUT_DIR/runs.jsonl"
: >"$LEDGER"

GIT_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | head -1)"
[ -n "$GIT_DIRTY" ] && GIT_DIRTY="dirty" || GIT_DIRTY="clean"
BIN_SHA256="$(sha256sum "$NODE_BIN" 2>/dev/null | cut -d' ' -f1)"
BIN_VERSION="$("$NODE_BIN" --version 2>/dev/null | head -1)"

echo "c3-stopwatch-triple: peer=$PEER file_peer=${FILE_PEER:-<none>} runs=$RUNS budget=${BUDGET}s"
echo "c3-stopwatch-triple: bin=$NODE_BIN"
echo "c3-stopwatch-triple: git=$GIT_COMMIT ($GIT_DIRTY) version=\"$BIN_VERSION\" sha256=$BIN_SHA256"
echo "c3-stopwatch-triple: out=$OUT_DIR"

# One sanity read of the peer BEFORE spending a budget on it. A peer whose own
# RPC cannot state a tip cannot be the thing a hash check compares against, and
# discovering that after 600 seconds is a waste of the window.
_pre_probe="$(tip_h_hash "$(tip_doc "$PEER_DATADIR" "$PEER_RPCPORT")")"
if [ "${_pre_probe%% *}" = "-1" ]; then
    echo "c3-stopwatch-triple: SKIP (peer tip unreadable via $PEER_DATADIR rpcport=$PEER_RPCPORT — is the fixture peer running?)"
    exit 2
fi
echo "c3-stopwatch-triple: peer tip readable: $_pre_probe"

run_scratch=""
poller_pid=""
cleanup_run() {
    if [ -n "$poller_pid" ]; then
        kill "$poller_pid" 2>/dev/null || true
        wait "$poller_pid" 2>/dev/null || true
        poller_pid=""
    fi
    if [ -n "$run_scratch" ]; then
        # The single-run harness owns datadir cleanup. Preserve any residue
        # on failure; this driver only removes its empty containing directory.
        rmdir -- "$run_scratch" 2>/dev/null || \
            echo "c3-stopwatch-triple: scratch retained: $run_scratch" >&2
        run_scratch=""
    fi
}
trap cleanup_run EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

overall=0
run=1
while [ "$run" -le "$RUNS" ]; do
    echo
    echo "──────── run $run/$RUNS ────────"
    peer_before="$(tip_h_hash "$(tip_doc "$PEER_DATADIR" "$PEER_RPCPORT")")"
    pb_h="${peer_before%% *}"; pb_hash="${peer_before##* }"
    echo "run $run: peer tip BEFORE  h=$pb_h hash=$pb_hash"

    # Bind discovery to this run, under the same configured scratch parent as
    # the single-run harness. A global /tmp glob misses the default location
    # and can query another run's client. The cookie also excludes ISO_HOME.
    run_scratch="$(mktemp -d "$CS_ROOT/zcl-c3-triple.XXXXXX")" || {
        echo "c3-stopwatch-triple: SKIP (create the private scratch root or set ZCL_CS_ROOT: $CS_ROOT)" >&2
        exit 2
    }
    client_trace="$OUT_DIR/run$run.client-tip.tsv"
    printf 'unix_s\theight\thash\n' >"$client_trace"
    (
        while :; do
            for _dd in "$run_scratch"/zcl-c3-stopwatch.*; do
                [ -f "$_dd/.cookie" ] || continue
                _t="$(tip_h_hash "$(tip_doc "$_dd" "$CLIENT_RPCPORT")")"
                [ "${_t%% *}" = "-1" ] && continue
                printf '%s\t%s\t%s\n' "$(date +%s)" "${_t%% *}" "${_t##* }" >>"$client_trace"
            done
            sleep 10
        done
    ) &
    poller_pid=$!

    run_log="$OUT_DIR/run$run.harness.log"
    ZCL_CS_ROOT="$run_scratch" \
    ZCL_CS_RUN_ID="triple$run-$(date -u +%Y%m%dT%H%M%SZ)-$$" \
    bash "$SCRIPT_DIR/cold_start_to_tip_stopwatch.sh" \
        --bin="$NODE_BIN" --peer="$PEER" --budget="$BUDGET" \
        ${FILE_PEER:+--file-peer="$FILE_PEER"} >"$run_log" 2>&1
    rc=$?
    cleanup_run

    peer_after="$(tip_h_hash "$(tip_doc "$PEER_DATADIR" "$PEER_RPCPORT")")"
    pa_h="${peer_after%% *}"; pa_hash="${peer_after##* }"
    echo "run $run: peer tip AFTER   h=$pa_h hash=$pa_hash"

    verdict="$(classify_exit "$rc")"
    artifact="$(sed -n 's/^cold-start-wipe-stopwatch: artifact=//p' "$run_log" | tail -1)"
    proof="${artifact:-}/proof.json"
    wall="null"; boots="null"; fh="-1"; fnt="-1"; blockers="-"
    if [ -n "$artifact" ] && [ -f "$proof" ]; then
        _pj="$(cat "$proof" 2>/dev/null)"
        wall="$(json_field "$_pj" wall_clock_seconds)"
        boots="$(json_field "$_pj" boots)"
        fh="$(json_field "$_pj" final_hstar)"
        fnt="$(json_field "$_pj" final_network_tip)"
        cp -f "$proof" "$OUT_DIR/run$run.proof.json" 2>/dev/null
        [ -f "$artifact/samples.tsv" ] && cp -f "$artifact/samples.tsv" "$OUT_DIR/run$run.samples.tsv" 2>/dev/null
        blockers="$(awk -F'\t' 'NR>1 && $NF != "-" {b=$NF} END{print (b==""?"-":b)}' \
                        "$artifact/samples.tsv" 2>/dev/null || echo -)"
    fi
    # The client's LAST successfully-read tip during the run. If the run passed,
    # this is the tip it reached; if it did not, it is how far it got, and either
    # way it is a real reading or the -1 sentinel.
    ct="$(awk -F'\t' 'NR>1 {h=$2; hs=$3} END{ if (h=="") print "-1 -"; else print h" "hs }' \
              "$client_trace" 2>/dev/null || echo "-1 -")"
    ch="${ct%% *}"; chash="${ct##* }"
    hv="$(hash_verdict "$ch" "$chash" "$pb_h" "$pb_hash")"
    # A run whose client tip does not match the tip the peer held when the run
    # STARTED may still match the tip the peer held when it ENDED — the peer is
    # a live node and its tip advances under us. Both are recorded; the second
    # is what makes a moving target readable instead of a false mismatch.
    hv_after="$(hash_verdict "$ch" "$chash" "$pa_h" "$pa_hash")"

    within="$( [ "$verdict" = "pass" ] && printf yes || printf no )"
    printf '{"run":%s,"verdict":"%s","exit_code":%s,"within_budget":"%s","wall_clock_seconds":%s,"budget_seconds":%s,"boots":%s,"git_commit":"%s","git_tree":"%s","bin_version":"%s","bin_sha256":"%s","peer":"%s","file_peer":"%s","peer_tip_before_h":%s,"peer_tip_before_hash":"%s","peer_tip_after_h":%s,"peer_tip_after_hash":"%s","final_hstar":%s,"final_network_tip":%s,"client_last_tip_h":%s,"client_last_tip_hash":"%s","hash_verdict_vs_peer_before":"%s","hash_verdict_vs_peer_after":"%s","last_blocker_ids":"%s","artifact":"%s"}\n' \
        "$run" "$verdict" "$rc" "$within" "${wall:-null}" "$BUDGET" "${boots:-null}" \
        "$GIT_COMMIT" "$GIT_DIRTY" "$BIN_VERSION" "$BIN_SHA256" "$PEER" "$FILE_PEER" \
        "$pb_h" "$pb_hash" "$pa_h" "$pa_hash" "${fh:--1}" "${fnt:--1}" \
        "$ch" "$chash" "$hv" "$hv_after" "$blockers" "${artifact:-}" >>"$LEDGER"

    echo "run $run: verdict=$verdict rc=$rc wall=${wall}s boots=${boots} H*=$fh network_tip=$fnt"
    echo "run $run: client last tip h=$ch hash=$chash"
    echo "run $run: hash vs peer-before=$hv  vs peer-after=$hv_after"
    [ "$verdict" = "pass" ] || overall=1
    case "$hv:$hv_after" in *agree*) ;; *) overall=1 ;; esac
    run=$((run + 1))
done

echo
echo "════════ c3-stopwatch-triple summary ════════"
printf '%-4s %-14s %-6s %-9s %-11s %-11s %s\n' run verdict wall H\* peer_tip_h hash cause
while IFS= read -r l; do
    printf '%-4s %-14s %-6s %-9s %-11s %-11s %s\n' \
        "$(json_field "$l" run)" "$(json_field "$l" verdict)" \
        "$(json_field "$l" wall_clock_seconds)" "$(json_field "$l" final_hstar)" \
        "$(json_field "$l" peer_tip_before_h)" \
        "$(json_field "$l" hash_verdict_vs_peer_after)" \
        "$(json_field "$l" last_blocker_ids)"
done <"$LEDGER"
echo "ledger=$LEDGER"
if [ "$overall" = "0" ]; then
    echo "VERDICT: PASS — every run reached the peer's tip height with an agreeing tip hash inside ${BUDGET}s"
else
    echo "VERDICT: FAIL — at least one run missed the ${BUDGET}s bar or could not be hash-confirmed against the peer"
fi
exit "$overall"
