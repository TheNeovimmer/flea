#!/usr/bin/env bash
# tools/flea-aur-versions checks the AUR carries the versions a release tag published,
# read here from saved RPC replies so no network is needed.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
checks=0
failed=0
check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s: expected [%s] got [%s]\n' "$1" "$2" "$3"; failed=$((failed + 1)); fi
}

out=$(tools/flea-aur-versions --json tests/aur-versions-pass.json 0.3.7 abc1234def 2>&1)
status=$?
check "the pass fixture exits 0" "0" "$status"
check "the pass fixture prints one line per package" "3" "$(printf '%s\n' "$out" | grep -c ': ok ')"

for pkg in flea fleabin fleagit; do
    out=$(tools/flea-aur-versions --json "tests/aur-versions-mismatch-$pkg.json" 0.3.7 abc1234def 2>&1)
    status=$?
    check "the $pkg mismatch exits nonzero" "1" "$status"
done
out=$(tools/flea-aur-versions --json tests/aur-versions-mismatch-fleabin.json 0.3.7 abc1234def 2>&1)
check "the missing package is named" "flea-bin: MISMATCH missing from the AUR reply, want 0.3.7-1" "$(printf '%s\n' "$out" | grep '^flea-bin:')"
out=$(tools/flea-aur-versions --json tests/aur-versions-mismatch-fleagit.json 0.3.7 abc1234def 2>&1)
check "the stale flea-git line names both versions" "flea-git: MISMATCH got 0.3.6.r0.g98404bc-1, want 0.3.7.r0.gabc1234-1" "$(printf '%s\n' "$out" | grep '^flea-git:')"

tools/flea-aur-versions >/dev/null 2>&1; check "no args exits 2" "2" "$?"
tools/flea-aur-versions --json tests/aur-versions-pass.json 0.3 >/dev/null 2>&1; check "a short version exits 2" "2" "$?"
tools/flea-aur-versions --json tests/aur-versions-pass.json 0.3.7 abc >/dev/null 2>&1; check "a short commit exits 2" "2" "$?"
tools/flea-aur-versions --json tests/does-not-exist.json 0.3.7 abc1234def >/dev/null 2>&1; check "a missing reply exits 2" "2" "$?"

printf 'aur-versions: %d check(s), %d failed\n' "$checks" "$failed"
[ "$failed" -eq 0 ]
