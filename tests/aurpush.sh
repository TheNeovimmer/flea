#!/usr/bin/env bash
# packaging/aur-push pushes only flea, flea-bin and flea-git, because its key reaches every package the AUR account maintains.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
checks=0
failed=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3"; failed=$((failed + 1)); fi
}
box=$(mktemp -d "${TMPDIR:-/tmp}/flea-aurpush.XXXXXX") || exit 1
trap 'rm -rf -- "$box"' EXIT
printf 'pkgname=flea\npkgver=0.0.1\npkgrel=1\narch=(any)\n' > "$box/PKGBUILD"

# Fail closed: git may only speak file://, so nothing here can reach the real AUR whatever aur-push does with its remote.
export GIT_ALLOW_PROTOCOL=file AUR_REMOTE_BASE="file://$box/remote"
export AUR_COMMIT_NAME='Flea test' AUR_COMMIT_EMAIL='flea-test@example.invalid'
# Stand-ins for the agent tools log every call, so a refused name is seen never to reach the key.
mkdir -p "$box/bin"
for tool in ssh-agent ssh-add; do
    printf '#!/bin/sh\nprintf "%%s\\n" "%s" >> "%s/agent.log"\ncat >/dev/null\n' "$tool" "$box" > "$box/bin/$tool"
    chmod 755 "$box/bin/$tool"
done
push() { env PATH="$box/bin:$PATH" AUR_SSH_KEY='not a key, only a sentinel' packaging/aur-push "$@" </dev/null; }

for name in other-package flea- 'flea bin' ../flea FLEA flea-git.git; do
    out=$(push "$name" "$box/PKGBUILD" 'test' 2>&1)
    status=$?
    check "'$name' is refused" "2 aur-push: refusing '$name', which is not flea, flea-bin or flea-git" "$status ${out##*$'\n'}"
done
check "no refused name reached the agent or the key" "" "$(cat "$box/agent.log" 2>/dev/null)"
# The control: an allowed name with a key does reach the stand-in agent, so the empty log above is the stand-ins not being called.
push flea "$box/PKGBUILD" 'test' > /dev/null 2>&1
check "an allowed name with a key reaches the stand-in agent" "ssh-agent" "$(head -1 "$box/agent.log" 2>/dev/null)"

# Each allowed name passes the allowlist and stops at the next check, a missing PKGBUILD, before anything else runs.
for name in flea flea-bin flea-git; do
    out=$(push "$name" "$box/missing/PKGBUILD" 'test' 2>&1)
    status=$?
    check "'$name' passes the allowlist" "1 aur-push: no file at '$box/missing/PKGBUILD'" "$status ${out##*$'\n'}"
done

# The whole push, to a local bare repository only; makepkg writes the .SRCINFO the AUR requires.
if command -v makepkg >/dev/null; then
    mkdir -p "$box/remote"
    git init -q --bare -b master "$box/remote/flea.git"
    git init -q -b master "$box/seed" && git -C "$box/seed" -c user.name=seed -c user.email=seed@example.invalid commit -q --allow-empty -m seed \
        && git -C "$box/seed" push -q "$box/remote/flea.git" master
    env -u AUR_SSH_KEY packaging/aur-push flea "$box/PKGBUILD" 'test: flea' > "$box/push.log" 2>&1 </dev/null
    status=$?
    check "flea is pushed to its own local repository" "0" "$status"
    [ "$status" -eq 0 ] || sed 's/^/  push: /' "$box/push.log"
    check "the pushed commit carries the given author" "Flea test <flea-test@example.invalid>" "$(git -C "$box/remote/flea.git" log -1 --format='%an <%ae>' master)"
else
    printf 'SKIP the whole push: makepkg is not installed here, the box runs it\n'
fi
# A stub makepkg stands in for the real one where it is not installed; docs/release.md states the flea-git ruling.
mkdir -p "$box/stubbin"
printf '#!/bin/sh\nif [ "${1:-}" = "--printsrcinfo" ]; then cat PKGBUILD; exit 0; fi\necho "stub makepkg: unexpected argv $*" >&2; exit 1\n' > "$box/stubbin/makepkg"
chmod 755 "$box/stubbin/makepkg"
stubpush() { env -u AUR_SSH_KEY PATH="$box/stubbin:$PATH" packaging/aur-push "$@" </dev/null; }
mkdir -p "$box/remote"
git init -q --bare -b master "$box/remote/flea-git.git"
mkdir -p "$box/gitseed"
printf 'pkgname=flea-git\npkgver=0.3.7.r0.gaaaaaaa\npkgrel=1\narch=(any)\n' > "$box/gitseed/PKGBUILD"
cp "$box/gitseed/PKGBUILD" "$box/gitseed/.SRCINFO"
git init -q -b master "$box/gitseed" && git -C "$box/gitseed" -c user.name=seed -c user.email=seed@example.invalid add PKGBUILD .SRCINFO \
    && git -C "$box/gitseed" -c user.name=seed -c user.email=seed@example.invalid commit -q -m seed \
    && git -C "$box/gitseed" push -q "$box/remote/flea-git.git" master
out=$(stubpush flea-git "$box/gitseed/PKGBUILD" 'flea-git v0.3.7' 2>&1)
status=$?
check "a byte-identical flea-git PKGBUILD pushes nothing" "0 aur-push: flea-git on the AUR already carries this PKGBUILD, so nothing is pushed" "$status ${out##*$'\n'}"
check "the no-op pushed no commit" "1" "$(git -C "$box/remote/flea-git.git" rev-list --count master)"
sed 's/^pkgver=.*/pkgver=0.3.7.r0.gbbbbbbb/' "$box/gitseed/PKGBUILD" > "$box/PKGBUILD.bumped"
out=$(stubpush flea-git "$box/PKGBUILD.bumped" 'flea-git v0.3.7' 2>&1)
status=$?
check "a pkgver-only change on flea-git is pushed" "0" "$status"
last=${out##*$'\n'}
check "the pushed line names flea-git" "aur-push: pushed flea-git as" "${last% *}"
check "the pkgver-only push is a second commit" "2" "$(git -C "$box/remote/flea-git.git" rev-list --count master)"
check "the pushed commit carries the given message" "flea-git v0.3.7" "$(git -C "$box/remote/flea-git.git" log -1 --format='%s' master)"
check "the AUR copy carries the new pkgver" "pkgver=0.3.7.r0.gbbbbbbb" "$(git -C "$box/remote/flea-git.git" show master:PKGBUILD | grep '^pkgver=')"
printf 'aurpush: %d check(s), %d failed\n' "$checks" "$failed"
[ "$failed" -eq 0 ]
