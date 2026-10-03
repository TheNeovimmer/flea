#!/usr/bin/env bash
# Real WindowBody, keys and QML models for the Sidebar040 and ClickAndRefresh bug hunt.
set -u
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
command -v qs >/dev/null || { echo 'FAIL sidebar-flows needs qs'; exit 1; }
command -v dbus-run-session >/dev/null || { echo 'FAIL sidebar-flows needs a private D-Bus session'; exit 1; }
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[[ -x "$bin" ]] || { echo 'FAIL sidebar-flows needs the built backend'; exit 1; }
sandbox_root_ok
probe=$(mktemp -d "$SANDBOX_ROOT/flea-sidebar-flows.XXXXXX") || exit 1
: > "$probe/$SANDBOX_MARKER" || exit 1
qs_pid=""
stop_qs() {
    [[ -n "$qs_pid" ]] || return 0
    local tick
    kill -TERM -- "-$qs_pid" 2>/dev/null || true
    for ((tick = 0; tick < 20; tick++)); do
        kill -0 -- "-$qs_pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 -- "-$qs_pid" 2>/dev/null; then
        kill -KILL -- "-$qs_pid" 2>/dev/null || true
        for ((tick = 0; tick < 20; tick++)); do
            kill -0 -- "-$qs_pid" 2>/dev/null || break
            sleep 0.1
        done
    fi
    wait "$qs_pid" 2>/dev/null || true
    if kill -0 -- "-$qs_pid" 2>/dev/null; then
        printf 'FAIL sidebar-flows owned process group %s survived teardown\n' "$qs_pid"
        return 1
    fi
    qs_pid=""
}
cleanup() { stop_qs || return 1; chmod u+w "$probe/home/readonly" 2>/dev/null; sandbox_remove "$probe"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$probe"/{home,config,state,data,cache,runtime} "$probe/home"/{fixture,readonly,Downloads} || exit 1
mkdir -p "$probe/data/Trash"/{files,info}
printf 'discarded\n' > "$probe/data/Trash/files/discarded.txt"
printf '[Trash Info]\nPath=%s\nDeletionDate=2026-09-23T10:00:00\n' "$probe/home/discarded.txt" > "$probe/data/Trash/info/discarded.txt.trashinfo"
chmod 700 "$probe/runtime"
printf 'a\n' > "$probe/home/fixture/a.txt"
printf 'b\n' > "$probe/home/fixture/b.txt"
ln -s a.txt "$probe/home/fixture/link.txt"
mkdir "$probe/home/fixture/sub"
printf 'read only\n' > "$probe/home/readonly/ro.txt"
touch -d '2000-01-01 00:00:00 UTC' "$probe/home/fixture/a.txt"
chmod 555 "$probe/home/readonly"
cat > "$probe/data/recently-used.xbel" <<XML
<?xml version="1.0"?><xbel version="1.0">
<bookmark href="file://$probe/home/fixture/a.txt" visited="2026-09-23T10:47:00Z"/>
<bookmark href="file://$probe/home/fixture/b.txt" visited="2026-09-22T09:12:00Z"/>
</xbel>
XML
env HOME="$probe/home" XDG_STATE_HOME="$probe/state" "$bin" --ui-state \
    '{"preview":{"column":false,"thumbnails":"off"},"updates":{"autoCheck":false}}' >/dev/null || exit 1
ln -s "$PWD/ui" "$probe/config/flea"
ln -s "$(readlink -f ui/boot/Commons)" "$probe/config/Commons"
ln -s "$(readlink -f ui/boot/Ui)" "$probe/config/Ui"
# The window loads its tab catcher from the shell directory, so the probe ships it as the product does.
ln -s "$PWD/ui/boot/fleatab.qml" "$probe/config/fleatab.qml"
cp tests/sidebar-flows.qml "$probe/config/shell.qml"
cp tests/sidebar-flows-extra.js "$probe/config/sidebar-flows-extra.js"
log="$probe/qs.log"
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
    HOME="$probe/home" XDG_STATE_HOME="$probe/state" XDG_CONFIG_HOME="$probe/config" \
    XDG_DATA_HOME="$probe/data" XDG_CACHE_HOME="$probe/cache" XDG_RUNTIME_DIR="$probe/runtime" \
    FLEA_PATH="$probe/home/fixture" FLEA_BIN="$bin" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 setsid dbus-run-session -- qs -p "$probe/config" >"$log" 2>&1 </dev/null &
qs_pid=$!
for ((tick = 0; tick < 600; tick++)); do
    grep -aq 'SIDEBAR_FLOWS DONE checks=[0-9]* failed=[0-9]*' "$log" && break
    sleep 0.1
done
stop_qs || exit 1
printf 'sidebar-flows: owned process group gone\n'
grep -aE 'SIDEBAR_FLOWS|TypeError|ReferenceError|ERROR|Cannot assign' "$log"
tally=$(grep -ao 'SIDEBAR_FLOWS DONE checks=[0-9]* failed=[0-9]*' "$log" | tail -1)
[[ -n "$tally" ]] || { printf 'FAIL sidebar-flows produced no completion receipt inside 60s; log tail:\n'; tail -20 "$log"; exit 1; }
[[ "$tally" == *' failed=0' ]] || exit 1
if grep -aqE 'TypeError|ReferenceError|ERROR|Cannot assign' "$log"; then
    echo 'FAIL sidebar-flows logged an engine error beside its receipt'
    exit 1
fi
