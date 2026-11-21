#!/bin/sh
set -eu
e=$1
c=512b94ff0c1b27c5586f55565f8e7a08b9e0fa1e
base=4c1487a1034ed0c88fcbe800c0d8fce4d1678b71
test "$(git rev-parse HEAD)" = "$c"
test "$(git rev-parse HEAD^)" = "$base"
test -z "$(git status --porcelain --untracked-files=no)"
test "$(git rev-list --count origin/main..HEAD)" = 1
bundle=$e/guidance.bundle
if test ! -s "$bundle"; then
    build/bin/z23-dev dev land send --lane=worldstream-contrib-handoff-guidance --commit="$c" --bundle_out="$bundle" > "$e/native-send.json"
fi
jq -e --arg c "$c" '.ok and .data.commit == $c' "$e/native-send.json" >/dev/null
jq -e --arg c "$c" --arg b "$base" '.commit == $c and .base == $b' "$bundle.offer.json" >/dev/null
git bundle verify "$bundle" && git bundle list-heads "$bundle"
test "$(sha256sum "$bundle" | cut -d" " -f1)" = "$(jq -r .bundle_sha256 "$bundle.offer.json")"
wc -c "$bundle"
sha256sum "$bundle"
