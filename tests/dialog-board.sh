#!/usr/bin/env bash
# DialogButtons040's critic findings, pinned on the shipped files: no check box draws a stray ground, the Trash strip's Back and Up are ChromeButtons, OpenWith's search field sits where the board puts it; offscreen, no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

verdict=0
fail() { printf 'FAIL %s\n' "$1"; verdict=1; }

# A Rectangle without its own colour paints Qt's default white, so none may enclose a Flea.CheckBox; a script, not a grep, since it follows nesting by indent.
colourless=$(python3 -B tests/dialog-board-sweep.py ui)
sweep_status=$?
[ "$sweep_status" -eq 0 ] || fail "the static sweep (tests/dialog-board-sweep.py) exited $sweep_status instead of reporting"
[ -z "$colourless" ] || fail "a colourless Rectangle wraps a Flea.CheckBox (Qt paints it white): $colourless"

if ! command -v qs >/dev/null; then
    echo "dialog-board.sh: qs is not installed, cannot draw the dialogs"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-dialog-board-XXXXXX") || exit 1
# GNU mktemp -d honours a relative TMPDIR verbatim, so the path is checked absolute and two components deep.
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home/.config" "$test_root/state" "$test_root/data" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/dialog-board.qml "$test_root/config/shell.qml" || exit 1

# The outer cap, passed to the harness as DIALOGBOARD_TIMEOUT_S so its own cap, half of it, lands first.
run_timeout_s=60
# Every XDG root is pinned under the marked root and no backend answers; the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_DATA_HOME="$test_root/data" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" DIALOGBOARD_ROOT="$test_root" DIALOGBOARD_TIMEOUT_S="$run_timeout_s" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout "$run_timeout_s" qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

# Every check a full green run makes, read off that run's own DONE line; a leg that stops running makes fewer and fails here.
expected_checks=25
# Sample input: "  INFO qml: DIALOGBOARD ok openwith: the card hosts 1 check box" once per check, and "  INFO qml: DIALOGBOARD DONE checks=25 failed=0" once.
passed=$(printf '%s\n' "$output" | grep -c 'DIALOGBOARD ok ')
failed=$(printf '%s\n' "$output" | grep -c 'DIALOGBOARD FAIL')
if [ "$failed" -ne 0 ]; then
    fail "the dialogs or the strip drifted from the board: $failed checks failed"
    printf '%s\n' "$output" | grep -a 'DIALOGBOARD FAIL'
fi
if ! printf '%s\n' "$output" | grep -q "DIALOGBOARD DONE checks=$expected_checks failed=0"; then
    fail "the run did not report $expected_checks checks and 0 failed"
    printf '%s\n' "$output" | grep -aE 'DIALOGBOARD DONE|ERROR|error' | head -10
fi
[ "$passed" -eq "$expected_checks" ] || fail "the run passed $passed checks by name, not $expected_checks"
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the dialog's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    fail 'the dialog-board harness logged a warning'
    printf '%s\n' "$warnings" | head -10
fi
if [ "$verdict" -ne 0 ]; then
    exit 1
fi
printf 'DIALOGBOARD PASS %s checks, check boxes on the dialog ground, strip marks are ChromeButtons, OpenWith spacing on the board\n' "$passed"
