#!/usr/bin/env bash
# Every focus ring that can reach an edge against the room its real host leaves, in the real WindowBody, offscreen.
set -u
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
command -v qs >/dev/null || { echo 'FAIL ring-bounds needs qs'; exit 1; }
command -v dbus-run-session >/dev/null || { echo 'FAIL ring-bounds needs a private D-Bus session'; exit 1; }
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[[ -x "$bin" ]] || { echo 'FAIL ring-bounds needs the built backend'; exit 1; }
sandbox_root_ok
probe=$(mktemp -d "$SANDBOX_ROOT/flea-ring-bounds.XXXXXX") || exit 1
: > "$probe/$SANDBOX_MARKER" || exit 1
qs_pid=""
# The run and each teardown wait are polled ten times a second (poll_s is one over polls_per_s) up to these bounds.
poll_s=0.1
polls_per_s=10
run_budget_s=60
stop_grace_s=2
run_polls=$(( run_budget_s * polls_per_s ))
stop_polls=$(( stop_grace_s * polls_per_s ))
stop_qs() {
    [[ -n "$qs_pid" ]] || return 0
    local tick
    kill -TERM -- "-$qs_pid" 2>/dev/null || true
    for ((tick = 0; tick < stop_polls; tick++)); do
        kill -0 -- "-$qs_pid" 2>/dev/null || break
        sleep "$poll_s"
    done
    if kill -0 -- "-$qs_pid" 2>/dev/null; then
        kill -KILL -- "-$qs_pid" 2>/dev/null || true
        for ((tick = 0; tick < stop_polls; tick++)); do
            kill -0 -- "-$qs_pid" 2>/dev/null || break
            sleep "$poll_s"
        done
    fi
    wait "$qs_pid" 2>/dev/null || true
    if kill -0 -- "-$qs_pid" 2>/dev/null; then
        printf 'FAIL ring-bounds owned process group %s survived teardown\n' "$qs_pid"
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
cp tests/ring-bounds.qml "$probe/config/shell.qml"
cp tests/ring-bounds.js "$probe/config/ring-bounds.js"
log="$probe/qs.log"
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
    HOME="$probe/home" XDG_STATE_HOME="$probe/state" XDG_CONFIG_HOME="$probe/config" \
    XDG_DATA_HOME="$probe/data" XDG_CACHE_HOME="$probe/cache" XDG_RUNTIME_DIR="$probe/runtime" \
    FLEA_PATH="$probe/home/fixture" FLEA_BIN="$bin" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 setsid dbus-run-session -- qs -p "$probe/config" >"$log" 2>&1 </dev/null &
qs_pid=$!
for ((tick = 0; tick < run_polls; tick++)); do
    grep -aq 'RINGBOUNDS DONE checks=[0-9]* failed=[0-9]*' "$log" && break
    sleep "$poll_s"
done
stop_qs || exit 1
printf 'ring-bounds: owned process group gone\n'
grep -aE 'RINGBOUNDS|TypeError|ReferenceError|ERROR|Cannot assign' "$log"
tally=$(grep -ao 'RINGBOUNDS DONE checks=[0-9]* failed=[0-9]*' "$log" | tail -1)
[[ -n "$tally" ]] || { printf 'FAIL ring-bounds produced no completion receipt inside %ss; log tail:\n' "$run_budget_s"; tail -20 "$log"; exit 1; }
[[ "$tally" == *' failed=0' ]] || exit 1
if grep -aqE 'TypeError|ReferenceError|ERROR|Cannot assign' "$log"; then
    echo 'FAIL ring-bounds logged an engine error beside its receipt'
    exit 1
fi
