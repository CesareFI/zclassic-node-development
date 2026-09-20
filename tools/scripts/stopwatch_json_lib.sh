# shellcheck shell=bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
#
# stopwatch_json_lib.sh — shared JSON/frontier-read and file-metadata primitives for the
# stopwatch/copy-prove harnesses (cold_start_to_tip_stopwatch.sh,
# network_disruption_recovery_stopwatch.sh, and siblings). Keep common
# observation helpers here. Sourcing contract: source AFTER REPO_ROOT is
# set, no cwd/global side effects beyond defining the functions below.

# Size and epoch mtime select fixtures; the remaining change stamp lets log
# observers reuse unchanged scans. BSD's seconds-only fallback cannot prove
# a same-size rewrite is unchanged, so it explicitly disables that cache.
stopwatch_file_metadata() {
    stat -c '%s %Y %d:%i:%s:%y:%z' -- "$1" 2>/dev/null ||
        stat -f '%z %m unavailable' "$1" 2>/dev/null
}

# json_escape <str> — backslash/quote/tab/cr-safe, newline-collapsed-to-space
# JSON string body (no surrounding quotes).
json_escape() {
    # Phase snapshots and proof artifacts emit many short strings during IBD.
    # Preserve the streaming helper's bytes without two external text tools.
    local s="$1"
    # Dense escapes make Bash replacement repeatedly copy large diagnostics.
    # Bound that work while retaining the process-free short-field path.
    if [ "${#s}" -gt 4096 ]; then
        local escaped
        # Collapse newlines first so command substitution can discard a sed
        # implementation's final newline without losing any input whitespace.
        escaped=$(printf '%s' "$s" | tr '\n' ' ' |
            sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g') || return
        printf '%s' "$escaped"
        return 0
    fi
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\t'/\\t}
    s=${s//$'\r'/\\r}
    s=${s//$'\n'/ }
    printf '%s' "$s"
}

# json_string <str> — json_escape() wrapped in double quotes.
json_string() {
    # Stream the quotes and escaped bytes without a nested shell per field.
    printf '"'
    json_escape "$1" || return
    printf '"'
}

# json_number_or_null <val> — <val> if it looks like an integer, else the
# bare JSON token null (never an unquoted empty/garbage field).
json_number_or_null() {
    case "${1:-}" in
        ''|*[!0-9-]*) printf 'null' ;;
        *) printf '%s' "$1" ;;
    esac
}

# jget <json> <key> — first integer match for a known field in a flat RPC
# document (not a general JSON parser; nested data belongs in jsonq). The
# "key"[..]: anchor with a required closing quote means "hstar" never
# matches "hstar_next_height" and "network_tip" never matches
# "network_tip_read_ok".
jget() {
    # Keep each poll's field reads inside Bash instead of starting three
    # external tools and four pipeline processes per field. Leave wide
    # counters as text: the caller owns range checks, never shell arithmetic.
    local pattern="\"$2\"[[:space:]]*:[[:space:]]*(-?[0-9]+)"
    if [[ "$1" =~ $pattern ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

# is_busy_response <frontier-doc> — true iff a `dumpstate reducer_frontier`
# body is the PARTIAL progress_store-busy doc —
# {"snapshot_status":"progress_store_busy","retryable":true} — rather than
# a genuine empty/absent response. A naive `grep -q '"hstar"'` miss cannot
# tell "the store is busy, retry" from "the node isn't answering at all"
# apart; this lets callers tell the two apart and label busy honestly
# instead of reading it as hstar=-1 or a silent empty.
is_busy_response() {
    # Polling must not start an external parser for this fixed telemetry key.
    # Exclude newline from whitespace to retain grep's line-local behavior.
    local pattern=$'"retryable"[[:blank:]\r\v\f]*:[[:blank:]\r\v\f]*true'
    [[ "$1" =~ $pattern ]]
}
