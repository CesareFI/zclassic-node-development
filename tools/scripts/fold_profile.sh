#!/bin/sh
# Copyright 2026 Rhett Creighton - Apache License 2.0
#
# fold_profile.sh — sample the reducer's cumulative fold telemetry on a datadir
# COPY and emit a CSV plus a derived per-stage / per-transaction summary.
#
# This is a THIN WRAPPER around tools/repro_on_copy.sh. That script already
# owns the parts that are easy to get dangerously wrong — snapshotting the live
# datadir to a fresh labelled copy, refusing to run against a live datadir or a
# live port, isolating HOME/rpcport/p2p/fs/https, and enforcing a deadline —
# and this script adds exactly one thing: a periodic sampler. There is no
# second harness here on purpose.
#
# WHAT IT ANSWERS
#   The node's per-stage timing array (drain_last_stage_us) describes only the
#   MOST RECENT drain round and is overwritten every round, so a sampled
#   observer almost always lands on a converged all-idle round and reads zeros.
#   The cumulative counters this script samples are monotonic, so the
#   DIFFERENCE between two samples is an exact interval measurement:
#     * per-stage microsecond share of a fold round (drain_stage_totals)
#     * write transactions per folded block, and what fraction of them are
#       EMPTY — opened, nothing advanced, rolled back (batch_*_total)
#     * microseconds per commit (batch_commit_us_total / commits)
#     * durability barriers per folded block (fsync_flush_count)
#     * proof_validate sub-phase split (reducer_stage_profile proof_validate)
#
# USAGE
#   tools/scripts/fold_profile.sh --slug fold-profile \
#       [--src DIR] [--deadline 3600] [--sample-secs 30] [--port 18299] \
#       [--connect IP:PORT] [--full] [--out DIR] [-- <node args...>]
#
#   --slug NAME       label for the copy + this run's artifacts (required)
#   --src DIR         source datadir (default $HOME/.zclassic-c23)
#   --deadline SECS   how long the copy node runs (default 3600)
#   --sample-secs N   sampling cadence (default 30)
#   --port N          isolated rpcport for the copy (default 18299)
#   --connect ADDR    peer for the copy to dial; without one the copy is
#                     isolated against a dead sink and folds nothing, which is
#                     a valid but empty measurement
#   --full            pass --full to repro_on_copy.sh (copies blocks/ too;
#                     required for anything that reads historical bodies)
#   --out DIR         artifact dir (default
#                     ~/.local/state/zclassic23-fold-profile/<slug>-<ts>)
#   --                everything after is passed verbatim to the copy node
#   Regression / observer-cost benchmark (no node or datadir required):
#     sh tools/scripts/fold_profile_selftest.sh --bench
#     sh tools/scripts/fold_profile_rpc_selftest.sh
#     sh tools/scripts/fold_profile_counts_selftest.sh
#
# HONESTY RULES
#   * Every number in the summary is a DIFFERENCE between two samples of a
#     monotonic counter taken from the running copy — never a single reading,
#     never a value transcribed from a doc.
#   * A run whose block delta is zero prints NO per-block figure. A fold that
#     did not fold cannot price a block, and printing a divide-by-zero dash is
#     the honest answer.
#   * The CSV is kept next to the summary so any figure can be recomputed.
#   * Failed or empty required RPC responses reject the whole sample; the
#     previous usable row remains the summary's final observation.
#   * Each telemetry client gets 5 seconds plus 1 second to terminate. A
#     stalled observer cannot hold the sampler forever or publish partial data.
#
# bash-free: sh + awk + sed; timeout (or gtimeout) bounds RPC clients.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NODE_BIN="${ZCL_NODE_BIN:-$REPO_ROOT/build/bin/zclassic23}"

SLUG=""
SRC="$HOME/.zclassic-c23"
DEADLINE=3600
SAMPLE_SECS=30
PORT=18299
CONNECT=""
FULL=""
OUTDIR=""
PASS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --slug=*)        SLUG="${1#--slug=}" ;;
        --slug)          shift; SLUG="${1:-}" ;;
        --src=*)         SRC="${1#--src=}" ;;
        --deadline=*)    DEADLINE="${1#--deadline=}" ;;
        --sample-secs=*) SAMPLE_SECS="${1#--sample-secs=}" ;;
        --port=*)        PORT="${1#--port=}" ;;
        --connect=*)     CONNECT="${1#--connect=}" ;;
        --full)          FULL="--full" ;;
        --out=*)         OUTDIR="${1#--out=}" ;;
        --)              shift; PASS="$*"; break ;;
        *) echo "fold_profile: unknown option '$1'" >&2; exit 2 ;;
    esac
    shift
done

[ -n "$SLUG" ] || { echo "fold_profile: --slug is required" >&2; exit 2; }
[ -x "$NODE_BIN" ] || {
    echo "fold_profile: $NODE_BIN not built — this harness measures a BINARY," >&2
    echo "              so there is nothing to sample without one." >&2
    exit 2
}
if command -v timeout >/dev/null 2>&1; then
    RPC_TIMEOUT_CMD=timeout
elif command -v gtimeout >/dev/null 2>&1; then
    RPC_TIMEOUT_CMD=gtimeout
else
    echo 'fold_profile: timeout or gtimeout is required to bound telemetry RPCs' >&2
    exit 2
fi

TS="$(date -u +%Y%m%dT%H%M%SZ)"
[ -n "$OUTDIR" ] || OUTDIR="$HOME/.local/state/zclassic23-fold-profile/$SLUG-$TS"
mkdir -p "$OUTDIR" || exit 2
CSV="$OUTDIR/samples.csv"
STATUS="$OUTDIR/copy_status.json"
REPRO_LOG="$OUTDIR/repro_on_copy.log"
SUMMARY="$OUTDIR/summary.txt"

# ── sampling primitives ─────────────────────────────────────────────────────
# Compact JSON, no jq (NO external dependencies is a project rule).

# jnums TEXT 'KEY ...' ['STAGE ...'] — scalar CSV followed by stage triples.
# Read drive counters and timings together from the same captured response.
# Preserve the former greedy sed reader: last integer match on the first
# matching line, zero when absent, and exact integer text (including wide counters).
# Once all columns are found, drain later lines without revisiting the columns.
# Match just the fields, retaining the last valid occurrence on the line.
# A greedy leading .* also copied and rescanned every preceding diagnostic.
# Skip regex scans for absent literal keys in sparse diagnostic responses.
# Start each regex at the located key so a large diagnostic prefix is not
# searched again. Keep the suffix for malformed and duplicate occurrences.
# Scalar matches use a growing integer window; stage matches stop at the first
# closing brace. Duplicate searches still inspect the entire line.
jnums() {
    printf '%s\n' "$1" | LC_ALL=C awk -v keys="$2" -v stages="${3:-}" '
        BEGIN {
            scalars = split(keys, key, " ")
            for (i = 1; i <= scalars; i++) {
                prefix[i] = "\"" key[i] "\":"
                literal[i] = prefix[i]
                pattern[i] = "^" prefix[i] "-?[0-9]+"
            }
            count = split(stages, stage, " ")
            n = scalars + count
            for (s = 1; s <= count; s++) {
                i = scalars + s
                literal[i] = "\"" stage[s] "\":"
                prefix[i] = "\"" stage[s] "\":\\{\"us\":"
                pattern[i] = prefix[i] "[0-9]+,\"calls\":[0-9]+,\"adv\":[0-9]+[,}]"
            }
        }
        {
            if (found == n) next
            for (i = 1; i <= n && found < n; i++) {
                if (i in value) continue
                start = index($0, literal[i])
                if (!start) continue
                matched = 0
                while (start) {
                    # Scalars need only the key and integer, not the entire
                    # diagnostic suffix. Grow for exact wide integer text.
                    window = i <= scalars ? length(literal[i]) + 32 : 128
                    rest = substr($0, start, window)
                    if (i > scalars) {
                        # A valid stage triple cannot cross a closing brace.
                        # Stop at a complete triple too: later fields in the
                        # same object do not contribute to this observation.
                        # Still grow for wide integers or malformed prefixes.
                        closing = index(rest, "}")
                        while (!closing && !match(rest, pattern[i]) &&
                               start + length(rest) <= length($0)) {
                            window *= 2
                            rest = substr($0, start, window)
                            closing = index(rest, "}")
                        }
                        if (closing) rest = substr(rest, 1, closing)
                    }
                    while (match(rest, pattern[i])) {
                        if (i <= scalars && RLENGTH == length(rest) &&
                            start + RLENGTH <= length($0)) {
                            window *= 2
                            rest = substr($0, start, window)
                            continue
                        }
                        v = substr(rest, RSTART, RLENGTH)
                        matched = 1
                        break
                    }
                    # Retry later keys after a malformed object; a match may
                    # have skipped a malformed key within this same object.
                    offset = start + length(literal[i])
                    if (i > scalars && RSTART > 0)
                        offset = start + RSTART + RLENGTH - 1
                    # Try nearby duplicates before copying the full suffix.
                    # Dense duplicate fields otherwise copy quadratic bytes.
                    # Overlap by the key length so split keys remain visible.
                    next_key = index(substr($0, offset, 256 + length(literal[i])), literal[i])
                    if (!next_key) {
                        next_key = index(substr($0, offset + 256), literal[i])
                        if (next_key) next_key += 256
                    }
                    start = next_key ? offset + next_key - 1 : 0
                }
                if (matched) {
                    sub("^" prefix[i], "", v)
                    if (i > scalars) {
                        gsub(/"calls":|"adv":/, "", v)
                        sub(/[,}]$/, "", v)
                    }
                    value[i] = v
                    found++
                }
            }
        }
        END {
            for (i = 1; i <= n; i++)
                printf "%s%s", (i == 1 ? "" : ","), (i in value ? value[i] : (i <= scalars ? "0" : "0,0,0"))
            printf "\n"
        }'
}

# jnums1 TEXT 'KEY ...' — ordered CSV of first matching integer values.
# The compact stage-profile dump emits cumulative before last_batch. Read
# each response once instead of starting three tools for each counter. Keep
# the old comma/line field boundaries, missing-value zero and integer text
# (awk arithmetic would round wide counters). Search each requested column
# directly, without allocating every comma-delimited field in a diagnostic
# tail. Skip regex scans for absent literal telemetry keys; incomplete profiles
# otherwise rescan that entire tail for every missing counter. Once complete,
# drain later lines; last_batch cannot replace values. Locate each literal key
# before applying the numeric regex so diagnostic prefixes are not rescanned.
jnums1() {
    printf '%s\n' "$1" | LC_ALL=C awk -v keys="$2" '
        BEGIN {
            n = split(keys, key, " ")
            for (i = 1; i <= n; i++) {
                field[i] = "\"" key[i] "\":"
                pattern[i] = "^" field[i] "-?[0-9]+"
            }
        }
        {
            if (found == n) next
            for (i = 1; i <= n; i++) {
                if (i in value) continue
                start = index($0, field[i])
                while (start) {
                    # Preserve (^|,)[^",]*: no quote may intervene between
                    # the key and its comma/line boundary, even on bad input.
                    before = start - 1
                    while (before > 0) {
                        c = substr($0, before, 1)
                        if (c == "\"" || c == ",") break
                        # Skip delimiter-free spans in bulk. Long diagnostic
                        # prefixes otherwise cost one awk step per byte.
                        # Jump to the nearest delimiter within the final
                        # span, retaining the exact quote/comma rule.
                        left = before > 128 ? before - 128 : 0
                        span = substr($0, left + 1, before - left)
                        if (match(span, /[",][^",]*$/)) {
                            before = left + RSTART
                        } else {
                            before = left
                        }
                    }
                    if (before == 0 || c == ",") {
                        # Ordinary counters fit without copying a diagnostic
                        # tail. Expand only if the integer reaches the edge;
                        # even unusually wide integer text stays exact.
                        window = length(field[i]) + 32
                        tail = substr($0, start, window)
                        while (match(tail, pattern[i])) {
                            if (RLENGTH == length(tail) &&
                                start + RLENGTH <= length($0)) {
                                window *= 2
                                tail = substr($0, start, window)
                                continue
                            }
                            v = substr(tail, length(field[i]) + 1,
                                       RLENGTH - length(field[i]))
                            value[i] = v
                            found++
                            break
                        }
                        if (i in value) break
                    }
                    offset = start + length(field[i])
                    # As in jnums, retry nearby keys without copying the
                    # entire suffix for each unavailable counter. Include
                    # key-length overlap so boundary-spanning keys survive.
                    next_key = index(substr($0, offset, 256 + length(field[i])), field[i])
                    if (!next_key) {
                        next_key = index(substr($0, offset + 256), field[i])
                        if (next_key) next_key += 256
                    }
                    start = next_key ? offset + next_key - 1 : 0
                }
            }
        }
        END {
            for (i = 1; i <= n; i++)
                printf "%s%s", (i == 1 ? "" : ","), (i in value ? value[i] : "0")
            printf "\n"
        }'
}

# jstages TEXT 'STAGE ...' — ordered us,calls,adv CSV triples.
# Batch the compact stage objects in one process. Preserve the former sed
# reader's last match on the first matching line, missing-stage zeros and
# exact integer text. Scalar drain_last_stage_us entries cannot match.
jstages() {
    jnums "$1" '' "$2"
}

STAGES="header_admit validate_headers body_fetch body_persist script_validate proof_validate utxo_apply tip_finalize"

ask() {
    # Keep the timeout status: a client can print a plausible response prefix
    # and then stall. sample_once rejects that entire observation. Kill after
    # the grace period even if the client ignores TERM.
    "$RPC_TIMEOUT_CMD" -k 1 5 "$NODE_BIN" -datadir="$COPY" -rpcport="$PORT" "$@" 2>/dev/null
}

# Command substitution removes trailing newlines, but leaves other blank RPC
# output intact. Reject it before further RPCs or zero-default field parsing.
has_sample_text() {
    case "$1" in
        *[![:space:]]*) return 0 ;;
        *) return 1 ;;
    esac
}

write_header() {
    h="ts,h_star,rounds_total"
    for s in $STAGES; do h="$h,${s}_us,${s}_calls,${s}_adv"; done
    h="$h,batch_opened,batch_committed,batch_rolled_back,batch_empty"
    h="$h,batch_commit_us_total,fsync_flush_count,fsync_flush_us_total"
    h="$h,pv_blocks,pv_total_us,pv_body_acquire_us,pv_verify_us,pv_log_insert_us"
    h="$h,pv_spends,pv_outputs,pv_sprout_groth16,pv_sprout_phgr13"
    h="$h,pv_binding_sigs,pv_lookahead_hits,pv_lookahead_misses"
    h="$h,tf_blocks,tf_total_us,ua_blocks,ua_total_us"
    printf '%s\n' "$h" > "$CSV"
}

sample_once() {
    # A failed command may still print a partial response. Check status and
    # presence before polling further or turning absent counters into zeros.
    if ! drive="$(ask ops state --subsystem=reducer_drive)" || ! has_sample_text "$drive"; then
        echo 'fold_profile: sample rejected: reducer_drive RPC failed or empty' >&2
        return 1
    fi
    if ! front="$(ask ops state --subsystem=reducer_frontier)" || ! has_sample_text "$front"; then
        echo 'fold_profile: sample rejected: reducer_frontier RPC failed or empty' >&2
        return 1
    fi
    if ! pv="$(ask ops state --subsystem=reducer_stage_profile --key=proof_validate)" || ! has_sample_text "$pv"; then
        echo 'fold_profile: sample rejected: proof_validate RPC failed or empty' >&2
        return 1
    fi
    if ! tf="$(ask ops state --subsystem=reducer_stage_profile --key=tip_finalize)" || ! has_sample_text "$tf"; then
        echo 'fold_profile: sample rejected: tip_finalize RPC failed or empty' >&2
        return 1
    fi
    if ! ua="$(ask ops state --subsystem=reducer_stage_profile --key=utxo_apply)" || ! has_sample_text "$ua"; then
        echo 'fold_profile: sample rejected: utxo_apply RPC failed or empty' >&2
        return 1
    fi

    row="$(date -u +%s),$(jnums "$front" provable_tip)"
    # The final read variable retains all stage triples. Reorder the captured
    # fields into the existing CSV schema using only shell builtins.
    IFS=, read -r rounds opened committed rolled_back empty commit_us flush_count flush_us stages <<EOF
$(jnums "$drive" 'drain_rounds_total batch_opened_total batch_committed_total batch_rolled_back_total batch_empty_total batch_commit_us_total fsync_flush_count fsync_flush_us_total' "$STAGES")
EOF
    row="$row,$rounds,$stages,$opened,$committed,$rolled_back,$empty,$commit_us,$flush_count,$flush_us"
    row="$row,$(jnums1 "$pv" 'blocks total_us pv_body_acquire_us pv_verify_us pv_log_insert_us pv_sapling_spends pv_sapling_outputs pv_sprout_groth16_joinsplits pv_sprout_phgr13_joinsplits pv_binding_sigs pv_lookahead_hits pv_lookahead_misses')"
    row="$row,$(jnums1 "$tf" 'blocks total_us')"
    row="$row,$(jnums1 "$ua" 'blocks total_us')"
    printf '%s\n' "$row" >> "$CSV"
    return 0
}

# ── launch the copy through the existing harness ────────────────────────────
set -- "$SLUG" "--src=$SRC" "--port=$PORT" "--deadline=$DEADLINE" \
       "--status-file=$STATUS"
[ -n "$FULL" ] && set -- "$@" "$FULL"
[ -n "$CONNECT" ] && set -- "$@" "--connect=$CONNECT"
[ -n "$PASS" ] && set -- "$@" -- $PASS

echo "[fold_profile] artifacts: $OUTDIR"
echo "[fold_profile] launching tools/repro_on_copy.sh $*"
"$REPO_ROOT/tools/repro_on_copy.sh" "$@" > "$REPRO_LOG" 2>&1 &
REPRO_PID=$!

# The copy path is only known once repro_on_copy.sh has snapshotted and
# launched; it publishes it in the status file.
COPY=""
waited=0
while [ "$waited" -lt 1800 ]; do
    if [ -f "$STATUS" ]; then
        COPY="$(sed -n 's/.*"copy_path":"\([^"]*\)".*/\1/p' "$STATUS" | head -1)"
        [ -n "$COPY" ] && break
    fi
    kill -0 "$REPRO_PID" 2>/dev/null || break
    sleep 5
    waited=$((waited + 5))
done
[ -n "$COPY" ] || {
    echo "[fold_profile] FAIL: no copy_path published (see $REPRO_LOG)" >&2
    wait "$REPRO_PID" 2>/dev/null
    exit 1
}
echo "[fold_profile] copy: $COPY"

write_header
samples=0
while kill -0 "$REPRO_PID" 2>/dev/null; do
    if sample_once; then samples=$((samples + 1)); fi
    sleep "$SAMPLE_SECS"
done
wait "$REPRO_PID"
REPRO_RC=$?
sample_once && samples=$((samples + 1))

echo "[fold_profile] $samples samples -> $CSV (repro rc=$REPRO_RC)"

# ── derive the table from the FIRST and LAST usable samples ─────────────────
# A stage can exceed 2^31 microseconds in 36 minutes. Format durations and
# cumulative counts as floating-point integers: some awk implementations
# narrow %d to signed 32 bits, turning positive observations negative.
# The sampler writes fixed-width CSV rows. Retain the endpoint records and
# split them once; intermediate samples only contribute to the sample count.
awk -F, -v OFS=' ' '
NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
{ if (!n) first = $0; last = $0; n++ }
function d(name) { return l[col[name]] - f[col[name]] }
END {
    if (n < 2) { print "fold_profile: fewer than 2 samples — nothing to difference"; exit 0 }
    split(first, f, ","); split(last, l, ",")
    secs = d("ts")
    printf "interval: %.0f s over %.0f samples\n\n", secs, n
    split("header_admit validate_headers body_fetch body_persist script_validate proof_validate utxo_apply tip_finalize", S, " ")
    tot = 0
    for (i = 1; i <= 8; i++) tot += d(S[i] "_us")
    print "STAGE                 delta_us      share%   calls   advances   us/advance"
    for (i = 1; i <= 8; i++) {
        us = d(S[i] "_us"); ca = d(S[i] "_calls"); ad = d(S[i] "_adv")
        printf "%-18s %12.0f %9.2f %7.0f %10.0f %12s\n", S[i], us,
               (tot > 0 ? 100.0 * us / tot : 0), ca, ad,
               (ad > 0 ? sprintf("%.1f", us / ad) : "-")
    }
    printf "%-18s %12.0f %9.2f %7.0f %10.0f\n\n", "TOTAL", tot, 100.0,
           d("rounds_total"), 0
    blocks = d("utxo_apply_adv")
    op = d("batch_opened"); cm = d("batch_committed"); em = d("batch_empty")
    printf "TRANSACTIONS\n"
    printf "  batches opened        %.0f\n", op
    printf "  batches committed     %.0f\n", cm
    printf "  batches rolled back   %.0f\n", d("batch_rolled_back")
    printf "  batches EMPTY         %.0f  (%.1f%% of opened)\n", em,
           (op > 0 ? 100.0 * em / op : 0)
    printf "  us per commit         %s\n",
           (cm > 0 ? sprintf("%.1f", d("batch_commit_us_total") / cm) : "-")
    printf "  durability barriers   %.0f\n", d("fsync_flush_count")
    printf "  us per barrier        %s\n",
           (d("fsync_flush_count") > 0 ? sprintf("%.1f", d("fsync_flush_us_total") / d("fsync_flush_count")) : "-")
    if (blocks > 0) {
        printf "  blocks folded         %.0f\n", blocks
        printf "  transactions/block    %.2f\n", op / blocks
        printf "  empty txns/block      %.2f\n", em / blocks
        printf "  barriers/block        %.2f\n", d("fsync_flush_count") / blocks
    } else {
        printf "  blocks folded         0  (no per-block figure: nothing folded)\n"
    }
    pvb = d("pv_blocks")
    printf "\nPROOF_VALIDATE (blocks=%.0f)\n", pvb
    if (pvb > 0) {
        printf "  total us/block        %.1f\n", d("pv_total_us") / pvb
        printf "    body acquire        %.1f\n", d("pv_body_acquire_us") / pvb
        printf "    proof sweep         %.1f\n", d("pv_verify_us") / pvb
        printf "    log insert          %.1f\n", d("pv_log_insert_us") / pvb
        printf "  sapling spends        %.0f\n", d("pv_spends")
        printf "  sapling outputs       %.0f\n", d("pv_outputs")
        printf "  sprout groth16        %.0f\n", d("pv_sprout_groth16")
        printf "  sprout phgr13         %.0f\n", d("pv_sprout_phgr13")
        printf "  binding sigs          %.0f\n", d("pv_binding_sigs")
        printf "  lookahead hit/miss    %.0f/%.0f\n", d("pv_lookahead_hits"),
               d("pv_lookahead_misses")
    } else {
        printf "  no proof_validate advance in the interval\n"
    }
}' "$CSV" | tee "$SUMMARY"

echo "[fold_profile] summary: $SUMMARY"
exit "$REPRO_RC"
