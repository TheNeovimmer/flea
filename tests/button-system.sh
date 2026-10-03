#!/usr/bin/env bash
# The Trash strip's Empty Trash and a destructive DialogButton draw one ladder in five states, and every ui/ file declaring the Button role and drawing a border.width is the control, a ruled set member, or named here; offscreen, no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

verdict=0
fail() { printf 'FAIL %s\n' "$1"; verdict=1; }

# The sweep table (ButtonSystem040 A, DESIGN-040 "buttons"): each file is the one control, a ruled set member, a mark, or deferred by name.
control_files="ConvertDialog MenuActionDialog CollideConfirm TrashConfirm OpenWithDialog NetworkDialog PickerSave PermissionsDialog TransferCard TrashView"
for name in $control_files; do
    grep -q 'Flea\.DialogButton {' "ui/$name.qml" || fail "ui/$name.qml no longer instantiates the one control, Flea.DialogButton"
done
grep -q 'inStrip: true' ui/TrashView.qml || fail 'ui/TrashView.qml: the strip action is not the control hosted in the strip'
# Rule 14: a checkbox is CheckBox.qml, drawn by none of its callers.
for name in OpenWithDialog ConvertDialog PermissionsDialog; do
    grep -q 'Flea\.CheckBox {' "ui/$name.qml" || fail "ui/$name.qml draws its own checkbox, not CheckBox.qml"
done
# A set's current member takes a foreground frame and foreground text and the rest muted ones: SettingsSegment.qml:38 ships it and ProtocolChip follows.
grep -q 'border.color: segment.current ? Theme.color.foreground : Theme.color.muted' ui/SettingsSegment.qml || fail 'ui/SettingsSegment.qml: the set member recipe moved'
grep -q 'border.color: root.picked || root.focused ? Theme.color.foreground : Theme.color.muted' ui/ProtocolChip.qml || fail 'ui/ProtocolChip.qml: the set member recipe moved'
# The QML handback test drives the ipc's own body: a focus scope forced alone returns to its last child, so the button is released first.
grep -q 'view\.emptyItem\.focus = false; view\.forceActiveFocus()' ui/Ipc.qml || fail 'ui/Ipc.qml: trashFocusListing no longer releases the strip button before forcing the view'
# Deferred by name (AGENTS.md): PickerChrome.Framed waits for Picker040 (v0.3.10), NetworkForm's TLS box has no board, and the marks carry no label.
grep -q 'component Framed: Item' ui/PickerChrome.qml || fail 'ui/PickerChrome.qml: Framed moved, update this table'
# Completeness: a ui/ file declaring the Button accessible role and drawing a border.width is in this list or it is a new hand-built button.
known="DialogButton DialogField MediaStrip PickerChrome ProtocolChip SettingsPanel SettingsSegment"
found=""
for path in $(grep -rlE 'Accessible\.role[[:space:]]*:[[:space:]]*Accessible\.(Push)?Button' ui --include='*.qml'); do
    grep -q 'border\.width' "$path" && found="$found $(basename "$path" .qml)"
done
found=$(printf '%s\n' $found | sort | tr '\n' ' ')
want=$(printf '%s\n' $known | sort | tr '\n' ' ')
[ "$found" = "$want" ] || fail "framed buttons in ui/ are [$found], the table names [$want]"
# The retired second recipe is named nowhere in the tree (this suite and the changelog's history excepted).
retired=$(grep -rIl --exclude-dir=.git --exclude-dir=target --exclude-dir=.superpowers --exclude-dir=.flea-local --exclude=CHANGELOG.md \
    'Chrome''Action' . 2>/dev/null | grep -v '^\./tests/button-system\.' || true)
[ -z "$retired" ] || fail "the retired second Empty Trash recipe is still named in: $retired"
[ ! -e ui/Chrome''Action.qml ] || fail 'ui/ChromeAction.qml is back'

if ! command -v qs >/dev/null; then
    echo "button-system.sh: qs is not installed, cannot draw the buttons"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-button-system-XXXXXX") || exit 1
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
cp tests/button-system.qml "$test_root/config/shell.qml" || exit 1

# The outer cap, passed to the harness as BUTTONSYS_TIMEOUT_S so its own cap, half of it, lands first.
run_timeout_s=60
# Every XDG root is pinned under the marked root and no backend answers; the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_DATA_HOME="$test_root/data" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_RUNTIME_DIR="$test_root/runtime" BUTTONSYS_ROOT="$test_root" BUTTONSYS_TIMEOUT_S="$run_timeout_s" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout "$run_timeout_s" qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

# Every check a full green run makes, read off that run's own DONE line; a leg that stops running makes fewer and fails here.
expected_checks=110
# Sample input: "  INFO qml: BUTTONSYS ok rest: ..." once per check, and "  INFO qml: BUTTONSYS DONE checks=110 failed=0" once.
passed=$(printf '%s\n' "$output" | grep -c 'BUTTONSYS ok ')
failed=$(printf '%s\n' "$output" | grep -c 'BUTTONSYS FAIL')
if [ "$failed" -ne 0 ]; then
    fail "the two buttons draw different ladders: $failed checks failed"
    printf '%s\n' "$output" | grep -a 'BUTTONSYS FAIL'
fi
if ! printf '%s\n' "$output" | grep -q "BUTTONSYS DONE checks=$expected_checks failed=0"; then
    fail "the run did not report $expected_checks checks and 0 failed"
    printf '%s\n' "$output" | grep -aE 'BUTTONSYS DONE|ERROR|error' | head -10
fi
[ "$passed" -eq "$expected_checks" ] || fail "the run passed $passed checks by name, not $expected_checks"
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the button's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    fail 'the button harness logged a warning'
    printf '%s\n' "$warnings" | head -10
fi
if [ "$verdict" -ne 0 ]; then
    exit 1
fi
printf 'BUTTONSYS PASS %s checks, strip and dialog draw one ladder\n' "$passed"
