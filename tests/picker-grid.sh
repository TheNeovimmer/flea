#!/usr/bin/env bash
# The picker grid asks thumbnails for visible tiles only, and its listing worker
# answers the fsinfo ask the window sends when its listed line lands. Offscreen
# with no display or lock: a real PickerGrid over stub rows plus a real
# PickerListing against a stub backend that answers listed and, only when asked,
# one fsinfo line.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "picker-grid.sh: qs is not installed, cannot drive the grid probe"
    exit 1
fi

# The C3 wiring itself: PickerWindow asks its listing worker for the class when
# the listing lands, the way the main pane asks its backend, see ui/js/Nav.js.
# The probe below proves the worker answers such an ask; this proves the window
# sends one, and it names the call so a moved ask reddens here rather than going
# silent into an icons-only grid.
grep -q "listing.fsinfo()" ui/PickerWindow.qml \
    || { echo "FAIL PickerWindow never asks the listing worker for fsinfo"; exit 1; }
grep -q "function fsinfo()" ui/PickerListing.qml \
    || { echo "FAIL PickerListing has no fsinfo ask to send"; exit 1; }

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-picker-grid.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/picker-grid.qml "$test_root/config/shell.qml" || exit 1

# A stub backend: listed plus its rows for a list, one local fsinfo line only for
# an fsinfo ask, silence for anything else. Unbuffered, so every line lands.
cat > "$test_root/stub-backend" <<'PYEND'
#!/usr/bin/env python3
import json, sys
def emit(o):
    sys.stdout.write(json.dumps(o) + "\n")
    sys.stdout.flush()
for line in sys.stdin:
    try:
        req = json.loads(line)
    except ValueError:
        continue
    if req.get("c") == "list":
        emit({"t": "listed", "n": 2, "read": 1.0, "sort": 1.0, "v": 1, "w": True, "path": req.get("path", "")})
        emit({"t": "rows", "start": 0, "rows": [{"n": "a.png", "d": False, "s": 10, "m": 1,
               "p": 33188, "i": "image-x-generic", "t": True, "k": 0}], "ms": 1.0, "kinds": []})
    elif req.get("c") == "fsinfo":
        emit({"t": "fsinfo", "fs": "tmpfs", "free": 123, "path": "/probe", "class": ""})
PYEND
chmod +x "$test_root/stub-backend" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    FLEA_BIN="$test_root/stub-backend" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: PICKERGRID PASS screen=0..19 scrolled<=39 fsinfo=\"\""
pass_count=$(printf '%s\n' "$output" | grep -c 'PICKERGRID PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'PICKERGRID FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the picker grid asked outside its visible tiles, or its worker never answered fsinfo\n'
    printf '%s\n' "$output" | grep -a 'PICKERGRID'
    printf '%s\n' "$output" | grep -aiE 'ERROR|error' | head -5
    printf '%s\n' "$output" | tail -5
    exit 1
fi
printf '%s\n' "$output" | grep -o 'PICKERGRID PASS.*'
