#!/bin/bash
# Catcher decisions and a real detached child that exits without acknowledging.
set -u
cd "$(dirname "$0")/.." || exit 1
bash tests/js.sh tabcatcher || exit 1
. tools/flea-sandbox-guard
sandbox_root_ok
probe=$(mktemp -d "$SANDBOX_ROOT/flea-tabcatcher.XXXXXX") || exit 1
: > "$probe/$SANDBOX_MARKER"
trap 'sandbox_remove "$probe"' EXIT
mkdir -p "$probe/bin" "$probe/config/tests" "$probe/home" "$probe/state" "$probe/runtime" || exit 1
chmod 700 "$probe/runtime"
ln -s "$PWD/tests/js" "$probe/config/tests/js"
ln -s "$PWD/ui" "$probe/config/ui"
cp tests/tabtearoff-failure.qml "$probe/config/shell.qml"
cp ui/TabDragGeometry.qml "$probe/config/geometry.qml"
cat > "$probe/flea-exits" <<'STUB'
#!/bin/bash
printf 'exited\n' > "$FLEA_STUB_MARKER"
exit 1
STUB
chmod +x "$probe/flea-exits"
cat > "$probe/bin/hyprctl" <<'GEOMETRY'
#!/bin/bash
x=100
if [[ -f "$FLEA_GEOMETRY_MARKER" ]]; then x=200; fi
printf 'parent=%s x=%s\n' "$PPID" "$x" >> "$FLEA_GEOMETRY_MARKER"
printf '[{"pid":%s,"at":[%s,0],"size":[900,500],"mapped":true,"hidden":false}]\n' "$PPID" "$x"
GEOMETRY
chmod +x "$probe/bin/hyprctl"
output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$probe/home" XDG_STATE_HOME="$probe/state" XDG_RUNTIME_DIR="$probe/runtime" \
    QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 QT_FORCE_STDERR_LOGGING=1 \
    PATH="$probe/bin:$PATH" FLEA_GEOMETRY_MARKER="$probe/geometry-queries" \
    FLEA_BIN="$probe/flea-exits" FLEA_STUB_MARKER="$probe/child-exited" \
    timeout 15 qs -p "$probe/config" 2>&1)
printf '%s\n' "$output"
printf 'GEOMETRY child runs: '; tr '\n' ';' < "$probe/geometry-queries"; printf '\n'
grep -q 'GEOMETRY PASS queryToken=latest' <<< "$output" || exit 1
grep -q 'LAUNCHACK PASS acknowledgments=1' <<< "$output" || exit 1
grep -q 'TEAROFF PASS stubExited=true sourceTabs=2' <<< "$output" || exit 1
echo 'tabcatcher: geometry, launch ack and tear-off checks passed'
