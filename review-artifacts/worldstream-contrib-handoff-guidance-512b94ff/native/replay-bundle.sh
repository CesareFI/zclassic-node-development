#!/bin/sh
set -eu
e=$1
w=$2
work=$(mktemp -d "$e/tmp/bundle-replay.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
git init --quiet --bare "$work"
git -C "$w" rev-parse --path-format=absolute --git-path objects > "$work/objects/info/alternates"
cd "$work"
git bundle unbundle "$e/guidance.bundle"
head=refs/z23-send/worldstream-contrib-handoff-guidance-512b94ff0c1b
tip=$(git bundle list-heads "$e/guidance.bundle" "$head" | cut -d' ' -f1)
test "$tip" = 512b94ff0c1b27c5586f55565f8e7a08b9e0fa1e
test "$(git rev-parse "$tip^")" = 4c1487a1034ed0c88fcbe800c0d8fce4d1678b71
test "$(git rev-parse "$tip^{tree}")" = a03faf573afd9b0b1d6dc54546d378dd986a4083
git diff --name-only "$tip^" "$tip"
git verify-pack -v objects/pack/*.idx | tail -1
printf '%s\n' 'Offline bundle unpack and pack verification passed. Commit, parent, tree and changed paths matched the review.'
