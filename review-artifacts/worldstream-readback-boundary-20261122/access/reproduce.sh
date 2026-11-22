#!/bin/sh
# Run as the existing unprivileged participant. Supply a new, unused fixture root.
set -eu
root=${1:?supply an absolute new synthetic directory}
runtime=${2:?supply the installed Codex runtime directory}
case "$root" in /*) ;; *) exit 64;; esac
test ! -e "$root"
src=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
umask 022
mkdir "$root" "$root/case" "$root/receiver" "$root/controller" "$root/other-case" "$root/recorder"
printf 'case\n' > "$root/case/allowed.txt"
printf 'receiver\n' > "$root/receiver/admin.txt"
printf 'controller\n' > "$root/controller/state.txt"
printf 'peer\n' > "$root/other-case/record.txt"
mkfifo "$root/recorder/pipe"
chmod 0220 "$root/recorder/pipe"
cp "$src/probe.py" "$root/case/probe.py"
cd "$root/case"
ln -s allowed.txt allowed.link
ln -s ../receiver/admin.txt admin.link
ln -s ../controller/state.txt state.link
ln -s ../other-case/record.txt record.link
ln -s ../recorder/pipe recorder.link
# Same account, same working directory, same fixtures before and after activating the profile.
printf '%s\n' SAME_ACCOUNT_CONTROL
/usr/bin/python3 -I ./probe.py
printf '%s\n' NAMED_PROFILE
"$runtime/codex" sandbox -C "$root/case" -P fixture \
    -c "permissions.fixture.filesystem={\":minimal\"=\"read\",\":workspace_roots\"=\"read\",\"$runtime\"=\"read\"}" \
    -c 'permissions.fixture.network.enabled=false' -- /usr/bin/python3 -I ./probe.py
