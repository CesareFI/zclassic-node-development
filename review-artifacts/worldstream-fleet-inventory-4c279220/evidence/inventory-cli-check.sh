#!/bin/sh
set -eu
umask 077
bin=$1
evidence=$2
fixture=$(mktemp -d "$evidence/after-state.XXXXXXXX")
export XDG_STATE_HOME="$fixture/state"
export HOME="$fixture/home"
export LC_ALL=C
out="$evidence/cli-last.json"
err="$evidence/cli-last.err"
count=0
call() {
    label=$1
    expected=$2
    shift 2
    start=$(date +%s%N)
    rc=0
    "$bin" "$@" >"$out" 2>"$err" || rc=$?
    stop=$(date +%s%N)
    bytes=$(wc -c <"$out")
    if [ "$expected" = OK ]; then
        test "$rc" = 0
        jq -e '.ok == true' "$out" >/dev/null
    else
        test "$rc" != 0
        jq -e --arg expected "$expected" '.ok == false and .error.code == $expected' "$out" >/dev/null
    fi
    printf '%s rc=%s result=%s elapsed_us=%s response_bytes=%s\n' "$label" "$rc" "$expected" "$(((stop-start)/1000))" "$bytes"
    count=$((count+1))
}
empty() { jq -e '.data.total == 0 and .data.joined == false and .data.machines == []' "$out" >/dev/null; }
tree() { find "$fixture" -mindepth 1 -printf '%P %y %m %s %T@ %C@\n' | sort; }
printf 'uid=%s fixture=%s\n' "$(id -u)" "$fixture"
tree > "$evidence/after-tree-before"
call missing-first OK fleet machines
empty
tree | cmp "$evidence/after-tree-before" -
call missing-repeat OK fleet machines
empty
tree | cmp "$evidence/after-tree-before" -
mkdir -m 700 "$XDG_STATE_HOME"
tree > "$evidence/after-tree-empty-base"
call empty-base-first OK fleet machines
empty
tree | cmp "$evidence/after-tree-empty-base" -
call empty-base-repeat OK fleet machines
empty
tree | cmp "$evidence/after-tree-empty-base" -
rmdir "$XDG_STATE_HOME"
ln -s missing-target "$XDG_STATE_HOME"
call dangling-ancestor FLEET_OPERATOR_UNREADABLE fleet machines
unlink "$XDG_STATE_HOME"
mkdir -m 000 "$XDG_STATE_HOME"
call inaccessible-ancestor FLEET_OPERATOR_UNREADABLE fleet machines
chmod 700 "$XDG_STATE_HOME"
call enroll-invite OK fleet invite --name=worldstream-fixture
fleet="$XDG_STATE_HOME/z23/dev/fleet"
test -s "$fleet/box.ed25519"
call valid-manager OK fleet machines
jq -e '.data.total == 0 and (.data.operator_pubkey|length)==64' "$out" >/dev/null
ln -s absent-roster "$fleet/machines.roster"
call invalid-roster FLEET_ROSTER_UNREADABLE fleet machines
unlink "$fleet/machines.roster"
: > "$fleet/operator.pub"
call malformed-pin FLEET_OPERATOR_UNREADABLE fleet machines
unlink "$fleet/operator.pub"
chmod 000 "$fleet/box.ed25519"
call inaccessible-key FLEET_KEY_UNAVAILABLE fleet machines
chmod 600 "$fleet/box.ed25519"
printf 'passed=%s failed=0 skipped=0\n' "$count"
