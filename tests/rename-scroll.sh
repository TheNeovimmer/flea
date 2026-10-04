#!/usr/bin/env bash
# The rename editor under real scrolling: ui/List.qml, ui/GridArea.qml and the shifted list origin, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "rename-scroll.sh: qs is not installed, cannot build the list or the grid"
    exit 1
fi

# The probe's showRow stub copies these two Pane.showRow branches, so a Pane that drops them must fail here, loudly.
for marker in 'else if (root.viewMode === "list") list.showCursor(view, context)' \
              'else root.listArea.positionViewAtIndex(view, ListView.Contain)'; do
    if ! grep -qF -- "$marker" ui/Pane.qml; then
        printf 'FAIL ui/Pane.qml no longer carries the showRow branch the probe stubs: %s\n' "$marker"
        exit 1
    fi
done

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-rename-scroll.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/rename-scroll-pane.qml "$test_root/config/RenamePaneStub.qml" || exit 1

total=0
bad=0
for mode in list grid origin; do
    # The origin probe is its own file, so a view's shell.qml is the one this mode runs.
    probe=tests/rename-scroll.qml
    [ "$mode" = origin ] && probe=tests/rename-scroll-origin.qml
    cp "$probe" "$test_root/config/shell.qml" || exit 1
    output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
        QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 RENAME_SCROLL_MODE="$mode" \
        timeout 60 qs -p "$test_root/config" 2>&1)
    # Sample input, one probe line: "  INFO qml: RENAMESCROLL MODE list checks=13 failed=0"
    line=$(printf '%s\n' "$output" | grep -a 'RENAMESCROLL MODE' | tail -1)
    mode_lines=$(printf '%s\n' "$output" | grep -ac "RENAMESCROLL MODE $mode ")
    checks=$(printf '%s\n' "$line" | sed -n 's/.*checks=\([0-9][0-9]*\) failed=.*/\1/p')
    failed=$(printf '%s\n' "$line" | sed -n 's/.*failed=\([0-9][0-9]*\).*/\1/p')
    noisy=$(printf '%s\n' "$output" | grep -aiE 'RENAMESCROLL FAIL|WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
    if [ "$mode_lines" -ne 1 ] || [ -z "$checks" ] || [ "$failed" != 0 ] || [ -n "$noisy" ]; then
        bad=$((bad + 1))
        printf 'FAIL the rename editor under %s scrolling lost its contract\n' "$mode"
        printf '%s\n' "$output"
        continue
    fi
    total=$((total + checks))
done

if [ "$bad" -ne 0 ]; then
    exit 1
fi
printf 'RENAMESCROLL DONE checks=%d failed=0\n' "$total"
