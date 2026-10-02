#!/usr/bin/env bash
# Real WindowBody, keys and QML models for the Sidebar040 and ClickAndRefresh bug hunt.
set -u
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
command -v qs >/dev/null || { echo 'FAIL sidebar-flows needs qs'; exit 1; }
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[[ -x "$bin" ]] || { echo 'FAIL sidebar-flows needs the built backend'; exit 1; }
sandbox_root_ok
probe=$(mktemp -d "$SANDBOX_ROOT/flea-sidebar-flows.XXXXXX") || exit 1
: > "$probe/$SANDBOX_MARKER" || exit 1
cleanup() { chmod u+w "$probe/home/readonly"; sandbox_remove "$probe"; }
trap cleanup EXIT
mkdir -p "$probe"/{home,config,state,data,cache,runtime} "$probe/home"/{fixture,readonly,Downloads} || exit 1
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
cp tests/sidebar-flows.qml "$probe/config/shell.qml"
output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
    HOME="$probe/home" XDG_STATE_HOME="$probe/state" XDG_CONFIG_HOME="$probe/config" \
    XDG_DATA_HOME="$probe/data" XDG_CACHE_HOME="$probe/cache" XDG_RUNTIME_DIR="$probe/runtime" \
    FLEA_PATH="$probe/home/fixture" FLEA_BIN="$bin" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 timeout 60 qs -p "$probe/config" 2>&1)
status=$?
printf '%s\n' "$output" | grep -aE 'SIDEBAR_FLOWS|TypeError|ReferenceError|ERROR|Cannot assign'
[[ "$status" == 143 ]] || { printf 'FAIL sidebar-flows exit=%s, expected owned termination 143\n' "$status"; exit 1; }
tally=$(printf '%s\n' "$output" | grep -o 'SIDEBAR_FLOWS DONE checks=[0-9]* failed=[0-9]*' | tail -1)
[[ -n "$tally" ]] || { printf 'FAIL sidebar-flows produced no completion receipt\n%s\n' "$output"; exit 1; }
[[ "$tally" == *' failed=0' ]] || exit 1
if printf '%s\n' "$output" | grep -aqE 'TypeError|ReferenceError|ERROR|Cannot assign'; then
    echo 'FAIL sidebar-flows logged an engine error beside its receipt'
    exit 1
fi
