#!/usr/bin/env bash
# The capture half of tools/mdspec-sheets: every spec example drawn by the real preview offscreen at body 14, judged on nothing but that each was captured.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
root=$PWD
capture_seconds=1500
if ! command -v qs >/dev/null; then
    echo "mdspec-shots.sh: qs is not installed, cannot render the preview"
    exit 1
fi
test_root="$FIXTURE_ROOT/flea-mdspec-shots-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" "$test_root/shots" || exit 1
chmod 700 "$test_root/runtime" || exit 1
python3 tools/mdspec-sheets/sheets.py manifest "$test_root" "${MDSPEC_SHEET_LIMIT:-0}" || exit 1
# The shell imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$root/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tools/mdspec-sheets/shell.qml "$test_root/config/shell.qml" || exit 1
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" XDG_RUNTIME_DIR="$test_root/runtime" \
    FLEA_SHEET_OUT="$test_root/shots" FLEA_SHEET_MD="$test_root/md" QML_XHR_ALLOW_FILE_READ=1 \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout "$capture_seconds" qs -p "$test_root/config" 2>&1 ) 2>/dev/null )
printf '%s\n' "$output" | grep -a -E 'MDSHEET' | tail -5
wanted=$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$test_root/md/manifest.json")
got=$(ls "$test_root/shots" | grep -c '\.png$')
if [ "$got" -ne "$wanted" ]; then
    printf 'FAIL mdspec-shots: %s of %s examples captured\n' "$got" "$wanted"
    exit 1
fi
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
    mkdir -p "$FLEA_CI_SUITE_LOGS/mdspec-shots" || exit 1
    cp "$test_root/shots/"*.png "$FLEA_CI_SUITE_LOGS/mdspec-shots/" || exit 1
fi
printf 'PASS mdspec-shots %s examples captured\n' "$got"
