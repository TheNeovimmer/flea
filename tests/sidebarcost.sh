#!/usr/bin/env bash
# Sidebar object counts and deferred menu work through real QML.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo 'FAIL sidebarcost: qs is missing'; exit 1; }
root=$(mktemp -d "$FIXTURE_ROOT/sidebarcost-XXXXXXXX") || exit 1
sandbox_require "$root" || exit 1
: > "$root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$root"' EXIT
mkdir -p "$root/config" "$root/home" "$root/state/flea" "$root/cache" "$root/runtime" "$root/data" "$root/home/a" "$root/home/b" "$root/home/c" || exit 1
chmod 700 "$root/runtime" || exit 1
ln -s "$PWD/ui" "$root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui" || exit 1
cp tests/sidebarcost.qml "$root/config/shell.qml" || exit 1
printf '%s\n' '{"updates":{"autoCheck":false},"places":{"showTrash":false,"showNetwork":false,"showDevices":false,"rail":"hidden","favourites":[{"label":"A","path":"~/a"},{"label":"B","path":"~/b"},{"label":"C","path":"~/c"}]}}' > "$root/state/flea/ui.json" || exit 1
printf '<xbel><bookmark href="file://%s/a/example.txt" visited="2026-09-30T12:00:00Z"/></xbel>\n' "$root/home" > "$root/data/recently-used.xbel" || exit 1
if grep -qE '^import "js/(Picker|Recent)\.js"' ui/Sidebar.qml; then
    echo 'FAIL sidebarcost: Sidebar still imports an action library at settle'
    exit 1
fi
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$root/home" XDG_STATE_HOME="$root/state" XDG_CACHE_HOME="$root/cache" XDG_RUNTIME_DIR="$root/runtime" \
    XDG_DATA_HOME="$root/data" \
    FLEA_BIN="$PWD/target/debug/flea" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$root/config" > "$root/probe.log" 2>&1
status=$?
cat "$root/probe.log"
[ "$status" -eq 0 ] || { printf 'FAIL sidebarcost: qs exit %s\n' "$status"; exit 1; }
[ "$(grep -c 'BOOTLOAD DONE .* checks, 0 failed' "$root/probe.log")" -eq 1 ] \
    || { echo 'FAIL sidebarcost: no single "BOOTLOAD DONE ... 0 failed" summary line'; exit 1; }
grep -qE 'BOOTLOAD FAIL|TypeError|ReferenceError|ERROR' "$root/probe.log" \
    && { echo 'FAIL sidebarcost: the probe log holds a BOOTLOAD FAIL, TypeError, ReferenceError or ERROR line'; exit 1; }
grep -E 'WARN' "$root/probe.log" | grep -vF 'This plugin does not support setting window masks' | grep -q . \
    && { echo 'FAIL sidebarcost: the probe log holds an unexpected WARN line'; exit 1; }
echo 'sidebarcost: sidebar and menu count gates passed'
