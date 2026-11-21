#!/bin/bash
set -euo pipefail
umask 077
e=$1
binary=$2
name=$3
length=$4
mkdir "$e/$name"
cd "$e/fixture/example"
sha=$(git rev-parse HEAD)
out="$e/$name/"
while (( ${#out} < length )); do out+=./; done
out+='example change.bundle'
t=$EPOCHREALTIME
GIT_ALLOW_PROTOCOL=file "$binary" dev land send "--commit=$sha" --lane=shared-example "--bundle_out=$out" --precheck=skip > "$e/$name/send.json" 2>"$e/$name/stderr"
end=$EPOCHREALTIME
jq -e --arg commit "$sha" '.ok==true and .data.commit==$commit and .data.lane=="shared-example"' "$e/$name/send.json" > /dev/null
jq -r '.data.next_action' "$e/$name/send.json" > "$e/$name/next-action.txt"
git bundle verify "$out" > "$e/$name/verify.txt" 2>&1
test "$(sha256sum "$out" | cut -d" " -f1)" = "$(jq -r '.data.bundle_sha256' "$e/$name/send.json")"
test -s "$out.offer.json"
{
  sha256sum "$binary"
  printf 'commit=%s path_bytes=%s response_bytes=%s bundle_bytes=%s\n' "$sha" "${#out}" "$(wc -c < "$e/$name/send.json")" "$(wc -c < "$out")"
  awk -v start="$t" -v end="$end" 'BEGIN { printf "elapsed_ms=%.3f\n", (end-start)*1000 }'
} > "$e/$name/receipt.txt"
