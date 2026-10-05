#!/usr/bin/env bash
# Headless proof of the real shebang receipt and the native case's strict completion wait.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo "FAIL menu-shebang: qs is not installed"; exit 1; }
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-menu-shebang-XXXXXXXX") || exit 1
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$test_root"' EXIT
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/menu-shebang.qml "$test_root/config/shell.qml" || exit 1
printf '#!/bin/sh\necho built\n' > "$test_root/build.sh"
printf 'plain notes\n' > "$test_root/notes.txt"
output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    FLEA_BIN="$PWD/target/debug/flea" SHEBANG_SCRIPT="$test_root/build.sh" SHEBANG_NOTES="$test_root/notes.txt" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 timeout 25 qs -p "$test_root/config" 2>&1)
status=$?
backend_checks=14
if [[ "$status" != 143 || $(grep -c 'MENUSHEBANG PASS' <<< "$output") != "$backend_checks" \
    || $(grep -c "MENUSHEBANG DONE checks=$backend_checks failures=0" <<< "$output") != 1 ]] \
    || grep -aqE 'MENUSHEBANG FAIL|WARN|ERROR|TypeError|ReferenceError' <<< "$output"; then
    printf 'FAIL menu-shebang: real backend/IPC proof, qs_exit=%s\n%s\n' "$status" "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'MENUSHEBANG PASS [^ ]*'

fail() { printf 'FAIL %s\n' "$*"; exit 1; }
wait_def=$(sed -n '/^makeexec_wait_shebang() {/,/^}/p' tests/ui.sh)
[[ -n "$wait_def" ]] || fail "menu-shebang: missing native wait"
eval "$wait_def"
async_wait_ms=5000
base='{"pane":"pane-B","opened":true,"hasRow":true,"shebangAsked":"/fixture/notes.txt","shebangId":3,"shebangHas":false,"shebangReply":{"pane":"pane-B","path":"/fixture/notes.txt","id":3,"hasShebang":false}}'
# Each incomplete or unrelated observation must be rejected before the matching negative receipt.
# Sample input: {"pane":"pane-B","opened":true,"hasRow":true,"shebangAsked":"/fixture/notes.txt","shebangId":3,"shebangHas":false,"shebangReply":{"pane":"pane-B","path":"/fixture/notes.txt","id":3,"hasShebang":false}}
jq -c '(.shebangReply = {}), (.shebangId = 2 | .shebangReply.id = 2),
    (.shebangReply.id = 1), (.shebangReply.path = "/fixture/build.sh"),
    (.shebangAsked = ""), (.opened = false), (.hasRow = false),
    (.shebangReply.hasShebang = true), (.shebangHas = true), (.shebangReply.pane = "pane-A"),
    (del(.pane, .shebangReply.pane)), .' <<< "$base" > "$test_root/observations" || exit 1
printf '0\n' > "$test_root/reads"
ipc() {
    local n
    n=$(cat "$test_root/reads")
    n=$((n + 1))
    printf '%s\n' "$n" > "$test_root/reads"
    sed -n "${n}p" "$test_root/observations"
}
makeexec_wait_shebang /fixture/notes.txt 2 || exit 1
incomplete_receipts=11
[[ $(cat "$test_root/reads") == $((incomplete_receipts + 1)) ]] || fail "menu-shebang: native wait accepted an incomplete receipt"
echo 'MENUSHEBANG PASS native-wait-rejects-eleven-incomplete-receipts'
# The timeout must name the retained path and state in one failure line, even when IPC fails.
async_wait_ms=150
ipc() { return 1; }
failure=$(makeexec_wait_shebang /fixture/notes.txt 2)
status=$?
[[ "$status" != 0 && "$failure" == 'FAIL makeexec: the plain-file probe never settled, expected=/fixture/notes.txt after=2 state=ipc-broken' ]] \
    || fail "menu-shebang: missing one-line failure diagnostic: $failure"
echo 'MENUSHEBANG PASS native-wait-refuses-broken-ipc'
echo "menu-shebang: $((backend_checks + 2)) checks, 0 failed"
