#!/usr/bin/env bash
# The picker's grid mode draws no column header; the probe drives the real window against a stub backend.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
if ! command -v qs >/dev/null; then
    echo "picker-header.sh: qs is not installed, cannot drive the header probe"
    exit 1
fi
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-picker-header.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/picker-header.qml "$test_root/config/shell.qml" || exit 1
# The real window launches in grid, from the remembered view.
mkdir -p "$test_root/state/flea" || exit 1
printf '{"pickerView":"grid"}' > "$test_root/state/flea/ui.json" || exit 1
: > "$test_root/reply.json" || exit 1
# Stub answers a folder with rows and fsinfo as local, so the grid asks no cache-only thumbs.
cat > "$test_root/stub-backend" <<'PYEND'
#!/usr/bin/env python3
import json, sys
if "--ui-state" in sys.argv:
    sys.stdout.write("{}")
    sys.stdout.flush()
    sys.exit(0)
def emit(o):
    sys.stdout.write(json.dumps(o) + "\n")
    sys.stdout.flush()
rows = [{"n": "photo%d.jpg" % i, "d": False, "s": 20480, "m": 1758835200, "p": 33188, "i": "image-x-generic", "t": True, "k": 0} for i in range(60)]
served_path = ""
for line in sys.stdin:
    # Sample input, one request per line: {"c":"list","path":"/winprobe","by":"name"}, {"c":"sort","by":"size","desc":false}, {"c":"window","start":0,"count":40}.
    try:
        req = json.loads(line)
    except ValueError:
        continue
    kind = req.get("c")
    if kind == "list":
        served_path = req.get("path", "")
        emit({"t": "listed", "n": 60, "read": 1.0, "sort": 1.0, "v": 1, "w": True, "path": served_path})
        emit({"t": "rows", "start": 0, "rows": rows, "ms": 1.0, "kinds": []})
    elif kind == "sort":
        emit({"t": "listed", "n": 60, "read": 0.0, "sort": 1.0, "v": 1, "w": True, "path": served_path})
    elif kind == "window":
        try:
            start = max(0, int(req.get("start", 0)))
            count = max(0, int(req.get("count", 0)))
        except (TypeError, ValueError):
            continue
        emit({"t": "rows", "start": start, "rows": rows[start:start + count], "ms": 1.0, "kinds": []})
    elif kind == "fsinfo":
        emit({"t": "fsinfo", "fs": "ext4", "free": 123, "path": served_path, "class": "local"})
    elif kind == "quit":
        break
PYEND
chmod +x "$test_root/stub-backend" || exit 1
# Sample input: '    readonly property int probeTimeoutMs: 30000'; the shell waits a margin longer so a hung stage reports itself.
probe_timeout_ms=$(sed -n 's/.*readonly property int probeTimeoutMs: *\([0-9][0-9]*\).*/\1/p' tests/picker-header.qml)
[ -n "$probe_timeout_ms" ] || { echo "picker-header.sh: probeTimeoutMs not found in tests/picker-header.qml"; exit 1; }
probe_timeout_margin=10
probe_timeout=$((probe_timeout_ms / 1000 + probe_timeout_margin))
output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    FLEA_BIN="$test_root/stub-backend" \
    FLEA_PICKER='{"mode":"open","title":"header probe","folder":"/winprobe"}' FLEA_PICKER_REPLY="$test_root/reply.json" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout "$probe_timeout" qs -p "$test_root/config" 2>&1)
# Sample input, one probe line: 'PICKERHEADER PASS grid header hidden, tiles under the strip, list header restored'.
pass_count=$(printf '%s\n' "$output" | grep -c 'PICKERHEADER PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'PICKERHEADER FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the picker drew a column header over the grid, or lost it in the list\n'
    printf '%s\n' "$output" | grep -a 'PICKERHEADER'
    printf '%s\n' "$output" | grep -aiE 'ERROR|error' | head -5
    printf '%s\n' "$output" | tail -5
    exit 1
fi
# A binding warning in the real window is a defect no check reads.
warn_lines=$(printf '%s\n' "$output" | grep -aE 'Unable to assign|TypeError|binding loop' | grep -a '\.qml' || true)
if [ -n "$warn_lines" ]; then
    printf 'FAIL the probe printed a QML warning:\n'
    printf '%s\n' "$warn_lines"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'PICKERHEADER PASS.*'
