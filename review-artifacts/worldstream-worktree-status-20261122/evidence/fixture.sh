#!/bin/sh
set -eu
# Run only inside a fresh controller-created case with private process inventory.
case_dir=$PWD
test -f synthetic-case
test "$(readlink /proc/self/ns/pid)" != "$(cat parent-pidns)"
test ! -e pool && test ! -e repo
export HOME="$case_dir/home" XDG_CONFIG_HOME="$case_dir/config" XDG_STATE_HOME="$case_dir/state" GIT_CONFIG_NOSYSTEM=1
mkdir -m 700 home config state pool
git init -q -b main --template= repo
printf 'synthetic tracked seed\n' > repo/seed.txt
git -C repo add seed.txt
git -C repo -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm seed
git -C repo worktree add -q -b held "$case_dir/pool/held"
git -C repo worktree add -q -b eligible "$case_dir/pool/eligible"
git -C repo show-ref --verify refs/heads/eligible > eligible-before
printf 'synthetic untracked note\n' > pool/held/notes.txt
printf 'bad index\n' > repo/.git/worktrees/held/index
for lane in eligible held; do
  touch -d '14 days ago' "pool/$lane" "repo/.git/worktrees/$lane/index" "repo/.git/worktrees/$lane/HEAD"
done
sha256sum pool/held/notes.txt repo/.git/worktrees/held/index > content-before
set +e
git -C pool/held --no-optional-locks status --porcelain --untracked-files=all > git-status.out 2> git-status.err
code=$?
set -e
test "$code" -ne 0
printf '%s\n' "$code" > git-status.exit
# Explicit synthetic root suppresses all default pools and the land queue.
for mode in false true; do
 input=$(jq -nc --arg p "$case_dir/pool" --argjson a "$mode" '{apply:$a,roots:[{class:"lanes",path:$p}]}')
 ./z23-dev ops host gc "--input=$input" > "gc-$mode.json"
 jq -e --arg held "$case_dir/pool/held" '.ok and (.data.needs_review|any(.path==$held)) and (.data.classes|length==1)' "gc-$mode.json" >/dev/null
 test -f pool/held/notes.txt
 sha256sum -c --quiet content-before
 if test "$mode" = false; then test -d pool/eligible; else test ! -e pool/eligible; fi
done
git -C repo show-ref --verify refs/heads/eligible > eligible-branch

cmp eligible-before eligible-branch
git -C repo show refs/heads/eligible:seed.txt | cmp - repo/seed.txt
