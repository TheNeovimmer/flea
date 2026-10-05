#!/usr/bin/env bash
# Another program creates, renames and deletes inside the open folder, and the real window must follow in every view; offscreen, no display.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { printf 'FAIL watch-views: qs is required\n'; exit 1; }
command -v dbus-run-session >/dev/null || { printf 'FAIL watch-views: dbus-run-session is required\n'; exit 1; }
test_root="$FIXTURE_ROOT/flea-watch-views-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,home,state/flea,cache,runtime,bin} || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$(readlink -m ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$PWD/ui/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp tests/watch-views.qml "$test_root/config/shell.qml" || exit 1
# The one process that changes the fixture from outside Flea, and it touches only paths under the fixture root.
cat > "$test_root/bin/outside" <<'SH'
#!/usr/bin/env bash
# Sample input: outside rename /home/flea-sandbox/flea-watch-views-1/fixture/parent/open/a.txt /home/flea-sandbox/flea-watch-views-1/fixture/parent/open/b.txt
set -u
root=${WATCHVIEWS_ROOT:?no fixture root}
inside() { case "$1" in "$root"/?*) return 0 ;; *) printf 'outside: %s is not under %s\n' "$1" "$root" >&2; exit 1 ;; esac; }
op=$1; shift
for path in "$@"; do inside "$path"; done
case "$op" in
    create) : > "$1" ;;
    mkdir) mkdir -- "$1" ;;
    rename) mv -- "$1" "$2" ;;
    delete) rm -- "$1" ;;
    rmdir) rmdir -- "$1" ;;
    *) printf 'outside: unknown op %s\n' "$op" >&2; exit 1 ;;
esac
SH
chmod +x "$test_root/bin/outside" || exit 1
fixture="$test_root/fixture"
timeout_seconds=${WATCHVIEWS_TIMEOUT:-170}
verdict=0
for mode in ${WATCHVIEWS_MODES:-list columns grid dual}; do
    sandbox_remove "$fixture"
    mkdir -p "$fixture/parent/open/sub" "$fixture/parent/sibling" "$fixture/other" || exit 1
    : > "$fixture/parent/open/sub/x.txt"
    for name in a b c; do : > "$fixture/parent/open/$name.txt"; done
    for name in o1 o2 o3; do : > "$fixture/other/$name.txt"; done
    if [ "$mode" = dual ]; then
        printf '{"view":"dual","dual":{"paths":["%s","%s"],"focus":0}}\n' "$fixture/parent/open" "$fixture/other" > "$test_root/state/flea/ui.json"
        named=""
    else
        printf '{"view":"%s"}\n' "$mode" > "$test_root/state/flea/ui.json"
        named="$fixture/parent/open"
    fi
    log="$test_root/$mode.log"
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
        XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BIN="$PWD/target/debug/flea" FLEA_PATH="$named" \
        WATCHVIEWS_UI="$PWD/ui" WATCHVIEWS_ROOT="$fixture" WATCHVIEWS_MODE="$mode" WATCHVIEWS_OUTSIDE="$test_root/bin/outside" \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        dbus-run-session -- bash -c 'timeout "$1" qs -p "$2" > "$3" 2>&1' _ "$timeout_seconds" "$test_root/config" "$log" 2> "$test_root/bus.log" ) 2>/dev/null
    status=$?
    # Sample input: "  INFO qml: WATCHVIEWS columns child-create updated total=4".
    grep -a 'WATCHVIEWS' "$log" || true
    if [ "$status" -ne 0 ] && [ "$status" -ne 143 ]; then printf 'FAIL watch-views: %s qs exit %s\n' "$mode" "$status"; verdict=1; fi
    if [ "$(grep -ac 'WATCHVIEWS DONE' "$log")" -ne 1 ]; then printf 'FAIL watch-views: %s sent no completion receipt\n' "$mode"; tail -20 "$log"; verdict=1; fi
    if grep -aqE 'WATCHVIEWS .* (STALE|FAIL)' "$log"; then printf 'FAIL watch-views: %s left a view stale\n' "$mode"; verdict=1; fi
    warnings=$(grep -aE 'TypeError|ReferenceError|ERROR|WARN' "$log" | grep -vF 'This plugin does not support setting window masks' || true)
    if [ -n "$warnings" ]; then printf 'FAIL watch-views: %s engine warnings\n%s\n' "$mode" "$warnings"; verdict=1; fi
done
[ "$verdict" -eq 0 ] && printf 'watch-views: every view followed every outside change\n'
exit "$verdict"
