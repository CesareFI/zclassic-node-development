#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Differential check of the real judge readers against their original regex
# substitutions. Optional --bench BASELINE times complete judge invocations on
# synthetic retained history; timings are observations, never pass thresholds.
set -euo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JUDGE="$SCRIPT_DIR/tip_agreement_judge.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/zcl-tip-parser.XXXXXX")"
trap 'rm -rf -- "$tmp"' EXIT

case "${1:-}" in
    '') [ "$#" -eq 0 ] ;;
    --bench) [ "$#" -eq 2 ] && [ -r "$2" ] ;;
    *) echo 'usage: tip_agreement_parser_selftest.sh [--bench BASELINE]' >&2; exit 2 ;;
esac

# Extract only the functions, never execute the judge or any node in this
# parser check. An absent/renamed reader makes awk fail, not silently pass.
sed -n '/^function num(/,/^BEGIN /{ /^BEGIN /!p; }' "$JUDGE" > "$tmp/readers.awk"
cat >> "$tmp/readers.awk" <<'AWK'
function oldnum(line, key,   s) {
    if (!match(line, "\"" key "\":-?[0-9]+")) return "";
    s = substr(line, RSTART, RLENGTH);
    sub("\"" key "\":", "", s);
    return s;
}
function oldstr(line, key,   s) {
    if (!match(line, "\"" key "\":\"[^\"]*\"")) return "";
    s = substr(line, RSTART, RLENGTH);
    sub("\"" key "\":\"", "", s);
    sub("\"$", "", s);
    return s;
}
function same(actual, expected, label) {
    # Prefix forces a byte-string comparison, including leading zeros/signs.
    if ("v" actual != "v" expected) {
        print "tip-parser: FAIL " label > "/dev/stderr";
        exit 1;
    }
    checks++;
}
BEGIN {
    nk=split("ts outcome modal_remote_peers min_distinct_peers contested_peers rival_heights_unresolved", keys);
    nv=split("0 2 -1 0002 -002 1800000000 123tail null true", values);
    for (k=1; k<=nk; k++) {
        key=keys[k];
        for (v=1; v<=nv; v++) {
            for (quoted=0; quoted<=1; quoted++) {
                val=(quoted ? "\"" values[v] "\"" : values[v]);
                for (pad=0; pad<=1; pad++) {
                    line="{\"ignored\":17,\"" key "\":" (pad ? " " : "") val ",\"" key "\":99}";
                    same(num(line,key),oldnum(line,key),"number " line);
                    same(str(line,key),oldstr(line,key),"string " line);
                }
            }
        }
        same(num("{}",key),"","absent number");
        same(str("{}",key),"","absent string");
        same(str("{\"" key "\":\"\"}",key),"","empty string");
    }
    same(num("{\"ts\":-002}","ts"),"-002","signed zero prefix");
    same(str("{\"outcome\":\"could-not-ask\"}","outcome"),"could-not-ask","outcome boundaries");
    printf "tip-parser: PASS (%d comparisons)\n", checks;
}
AWK
awk -f "$tmp/readers.awk"

if [ "${1:-}" = --bench ]; then
    # One year at the shipped 10-minute cadence. Dense input separately
    # exercises every field on 86,401 in-window rows (an observer stress case,
    # not the shipped cadence). All data and output stay in disposable files.
    for shape in retained dense; do
        if [ "$shape" = retained ]; then rows=52560; step=600
        else rows=86401; step=1; fi
        awk -v rows="$rows" -v step="$step" 'BEGIN {
            for(i=0;i<rows;i++) printf "{\"ts\":%d,\"outcome\":\"agrees\",\"modal_remote_peers\":2,\"min_distinct_peers\":2,\"contested_peers\":0,\"rival_heights_unresolved\":0}\n", 1800000000-i*step;
        }' > "$tmp/ledger.jsonl"
        for sample in 1 2 3; do
            for variant in baseline changed; do
                if [ "$variant" = baseline ]; then script="$2"; else script="$JUDGE"; fi
                TIMEFORMAT="$shape sample=$sample $variant wall=%3R user=%3U sys=%3S"
                time ZCL_PARITY_JUDGE_NOW=1800000000 bash "$script" "$tmp/ledger.jsonl" > "$tmp/$variant.out"
            done
            cmp "$tmp/baseline.out" "$tmp/changed.out"
        done
    done
fi
