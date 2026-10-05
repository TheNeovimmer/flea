#!/usr/bin/env bash
# Census the real window after a small listing settles, with no display or operator state.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { printf 'FAIL startup-objects: qs is required\n'; exit 1; }
command -v dbus-run-session >/dev/null || { printf 'FAIL startup-objects: dbus-run-session is required\n'; exit 1; }
test_root="$FIXTURE_ROOT/flea-startup-objects-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,home,state/flea,cache,runtime,fixture,bin} || exit 1
chmod 700 "$test_root/runtime" || exit 1
printf '{}\n' > "$test_root/state/flea/ui.json"
touch "$test_root/fixture/a.txt" "$test_root/fixture/b.txt" "$test_root/fixture/c.txt"
ln -s "$(readlink -m ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
# The window loads its tab catcher from the shell directory at startup, so the probe ships it as the product does.
ln -s "$PWD/ui/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp tests/startup-objects.qml "$test_root/config/shell.qml" || exit 1
power_disk=""
for stat_file in /sys/block/*/stat; do
    [ -r "$stat_file" ] || continue
    power_disk=${stat_file%/stat}
    power_disk="/dev/${power_disk##*/}"
    break
done
[ -n "$power_disk" ] || { printf 'FAIL startup-objects: no readable disk stat\n'; exit 1; }
probe_timeout_seconds=20
leg_timeout_seconds=$((probe_timeout_seconds + 1))
cat > "$test_root/bin/gio" <<'SH'
#!/usr/bin/env bash
# Sample input: gio mount -t /dev/sda, held without touching the device.
case "${1-} ${2-}" in
    'mount -t'|'mount -u') exec sleep "$STARTUP_OBJECTS_LEG_TIMEOUT_SECONDS" ;;
    *) exec /usr/bin/gio "$@" ;;
esac
SH
chmod +x "$test_root/bin/gio" || exit 1
log="$test_root/startup.log"
# The shell starts the GVfs trash daemon, so it runs on its own bus, whose daemons log to bus.log and stay out of the engine-warning scan.
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u QML_DISABLE_DISK_CACHE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BIN="$PWD/target/debug/flea" \
    FLEA_PATH="$test_root/fixture" STARTUP_OBJECTS_UI="$PWD/ui" STARTUP_OBJECTS_DISK="$power_disk" \
    PATH="$test_root/bin:$PATH" STARTUP_OBJECTS_LEG_TIMEOUT_SECONDS="$leg_timeout_seconds" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 QML_IMPORT_TRACE=1 \
    QT_LOGGING_RULES='qt.qml.diskcache*=true' \
    dbus-run-session -- bash -c 'timeout "$1" qs -p "$2" > "$3" 2>&1' _ "$probe_timeout_seconds" "$test_root/config" "$log" 2> "$test_root/bus.log" ) 2>/dev/null
status=$?
grep -a 'STARTUP_OBJECTS' "$log" || true
if [ "$status" -ne 0 ] && [ "$status" -ne 143 ]; then
    printf 'FAIL startup-objects: qs exit %s\n' "$status"
    cat "$log"
    exit 1
fi
warnings=$(grep -aE 'TypeError|ReferenceError|ERROR|WARN' "$log" | grep -vF 'This plugin does not support setting window masks' || true)
if [ -n "$warnings" ]; then
    printf 'FAIL startup-objects: engine warnings\n%s\n' "$warnings"
    exit 1
fi
trace_control=ui/js/Startup.js
# A silent trace cannot prove that the picker library stayed cold.
if ! grep -aFq "$trace_control" "$log"; then
    printf 'FAIL startup-objects: log %s has no loaded JS control %s\n' "$log" "$trace_control"
    exit 1
fi
if grep -aFq 'ui/js/Picker.js' "$log"; then
    printf 'FAIL startup-objects: the unused picker library loaded at startup\n'
    exit 1
fi
for static_input in ui/RailPlaces.qml ui/TrashHost.qml; do
    if [ ! -f "$static_input" ] || [ ! -r "$static_input" ]; then
        printf 'FAIL startup-objects: cannot read %s\n' "$static_input"
        exit 1
    fi
done
if grep -qE '^[[:space:]]*(readonly[[:space:]]+)?property .* entries:' ui/RailPlaces.qml; then
    printf 'FAIL startup-objects: the keymap-only places aggregate is eager\n'
    exit 1
fi
if grep -qE '^[[:space:]]*(readonly[[:space:]]+)?property var sheetPane:' ui/TrashHost.qml; then
    printf 'FAIL startup-objects: the keymap-only Trash pane uses a binding\n'
    exit 1
fi
if [ "$(grep -ac 'STARTUP_OBJECTS PASS' "$log")" -ne 1 ] \
    || [ "$(grep -ac 'STARTUP_OBJECTS DONE' "$log")" -ne 1 ] \
    || grep -aq 'STARTUP_OBJECTS FAIL' "$log"; then
    printf 'FAIL startup-objects: no clean completion receipt\n'
    cat "$log"
    exit 1
fi
printf 'startup-objects: 1 passed, 0 failed\n'
