#!/usr/bin/env bash
# Non-file surfaces draw no scroll bar and file surfaces keep their lane: source sweep plus offscreen rail and dialog wheel probe.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

verdict=0
# No bar and no lane off the file surfaces: a bar item cannot be visible if no file declares one.
nobar="ui/Sidebar.qml ui/PickerPlaces.qml ui/SettingsRail.qml ui/SettingsPane.qml ui/StatusBar.qml ui/CardScroll.qml ui/OpenWithDialog.qml"
for f in $nobar; do
    [ -f "$f" ] || { printf 'FAIL %s is missing\n' "$f"; verdict=1; continue; }
    if grep -q "ViewportScrollBar" "$f"; then
        printf 'FAIL %s still declares a scroll bar\n' "$f"
        verdict=1
    fi
done
# The lane stays exactly as it is on the surfaces that show files.
lane="ui/List.qml ui/GridArea.qml ui/ColumnPane.qml ui/PickerList.qml ui/PickerGrid.qml ui/TrashView.qml ui/PreviewText.qml ui/PreviewMarkdown.qml ui/PdfViewer.qml ui/PreviewColumn.qml"
for f in $lane; do
    if ! grep -q "ViewportScrollBar" "$f"; then
        printf 'FAIL %s lost its scroll lane\n' "$f"
        verdict=1
    fi
done
[ "$verdict" -ne 0 ] && exit 1

if ! command -v qs >/dev/null; then
    echo "scroll-lanes.sh: qs is not installed, cannot probe a rail"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-scroll-lanes-XXXXXX") || exit 1
# GNU mktemp honours a relative TMPDIR verbatim, so the made path is checked absolute first.
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/scroll-lanes.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input, one probe line: "  INFO qml: SCROLLLANES PASS rail=200 body=320/320 ..."
# Sample input, the receipt: "  INFO qml: SCROLLLANES DONE failures=0".
# The owned termination is the probe's own self-kill (SIGTERM, 143) after its one DONE receipt; a PASS beside any other status is a double's, never a proof.
pass_count=$(printf '%s\n' "$output" | grep -c 'SCROLLLANES PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'SCROLLLANES FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'SCROLLLANES DONE')
if [ "$qs_status" -ne 143 ]; then
    printf 'FAIL qs exited %s, want the owned self-kill 143 after DONE\n' "$qs_status"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE beside the PASS\n' "$done_count"
    verdict=1
fi
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a non-file surface kept a bar, lost full width, or stopped scrolling\n'
    printf '%s\n' "$output" | grep -aE 'SCROLLLANES|ERROR|error'
    verdict=1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the rail's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the lanes harness logged a warning\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'SCROLLLANES PASS.*'
printf 'SCROLLLANES STATUS qs_exit=%s done=1\n' "$qs_status"
