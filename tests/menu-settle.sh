#!/usr/bin/env bash
# A menu placed again while open with nothing new to draw still ends its pointer settle, and a menu opened by key or click reads its rows widths once per build; offscreen, so no display and no lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "menu-settle.sh: qs is not installed, cannot place a menu"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-menu-settle-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/menu-settle.qml "$test_root/config/shell.qml" || exit 1

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

# Sample input, the verdict line: "  INFO qml: MENU_SETTLE PASS the second place settled in 17 ms"
if [ "$(printf '%s\n' "$output" | grep -c 'MENU_SETTLE PASS')" -ne 1 ] || printf '%s\n' "$output" | grep -q 'MENU_SETTLE FAIL'; then
    printf 'FAIL a menu placed again with nothing to draw kept its pointer settle\n'
    printf '%s\n' "$output" | grep -aE 'MENU_SETTLE|ERROR|error' | head -20
    exit 1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the menu's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the menu harness logged a warning\n'
    printf '%s\n' "$warnings" | head -10
    exit 1
fi
printf '%s\n' "$output" | grep -o 'MENU_SETTLE PASS.*'

# The open-cost leg: the real pane opens its row menu by the m key and by a click point over the candidate backend.
bin=${FLEA_BIN:-$PWD/target/debug/flea}
command -v dbus-run-session >/dev/null || { echo 'FAIL menu-settle open-cost leg needs private D-Bus'; exit 1; }
[[ -x "$bin" ]] || { echo 'FAIL menu-settle open-cost leg needs the candidate backend'; exit 1; }
cost_root="$test_root/cost"
mkdir -p "$cost_root"/{home,config,state,data,cache,runtime} "$cost_root/home/fixture" || exit 1
chmod 700 "$cost_root/runtime" || exit 1
for name in a.txt b.txt c.txt d.txt e.txt f.txt g.txt h.txt i.txt j.txt; do printf 'open cost fixture\n' > "$cost_root/home/fixture/$name"; done
env HOME="$cost_root/home" XDG_STATE_HOME="$cost_root/state" "$bin" --ui-state \
    '{"view":"list","keys":"default","preview":{"column":false,"thumbnails":"off"},"updates":{"autoCheck":false},"display":{"textSize":{"mode":14}}}' >/dev/null || exit 1
ln -s "$PWD/ui" "$cost_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$cost_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$cost_root/config/Ui" || exit 1
ln -s "$PWD/ui/boot/fleatab.qml" "$cost_root/config/fleatab.qml" || exit 1
cp tests/menu-open-cost.qml "$cost_root/config/shell.qml" || exit 1
cost_run() {
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
        HOME="$cost_root/home" XDG_STATE_HOME="$cost_root/state" XDG_CONFIG_HOME="$cost_root/config" \
        XDG_DATA_HOME="$cost_root/data" XDG_CACHE_HOME="$cost_root/cache" XDG_RUNTIME_DIR="$cost_root/runtime" \
        FLEA_PATH="$cost_root/home/fixture" FLEA_BIN="$bin" FLEA_COST_FIRST="$1" GIO_USE_VOLUME_MONITOR=unix QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
        QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        timeout "$cost_limit_seconds" dbus-run-session -- qs -p "$cost_root/config" 2>&1
}
# Each process opens four menus, its own first one cold: the key path first, then the click path first.
readonly cost_limit_seconds=60 cost_qs_status=143 cost_checks=12
for first in key click; do
    cost_out=$(cost_run "$first")
    cost_status=$?
    # Sample input: "  INFO qml: MENUOPEN open 0 key reads=2 builds=2 frame_ms=11" then "MENUOPEN PASS 12 checks".
    if [ "$cost_status" -ne "$cost_qs_status" ] || ! printf '%s\n' "$cost_out" | grep -aq "MENUOPEN PASS $cost_checks checks" \
            || printf '%s\n' "$cost_out" | grep -aq 'MENUOPEN FAIL'; then
        printf 'FAIL a menu opened by %s read its rows widths once per row, or the leg did not finish (qs exit %s)\n' "$first" "$cost_status"
        printf '%s\n' "$cost_out" | grep -aE 'MENUOPEN|ERROR|error' | head -20
        exit 1
    fi
    cost_warnings=$(printf '%s\n' "$cost_out" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning")
    if [ -n "$cost_warnings" ]; then
        printf 'FAIL the open-cost leg logged a warning\n%s\n' "$cost_warnings" | head -10
        exit 1
    fi
    printf '%s\n' "$cost_out" | grep -ao 'MENUOPEN open .*'
done
printf 'MENUOPEN PASS both paths\n'
