#!/usr/bin/env bash
# Grid asks visible tiles only; probe drives the real window against a logging stub.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
if ! command -v qs >/dev/null; then
    echo "picker-grid.sh: qs is not installed, cannot drive the grid probe"
    exit 1
fi
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-picker-grid.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/picker-grid.qml "$test_root/config/shell.qml" || exit 1
: > "$test_root/requests" || exit 1
: > "$test_root/reply.json" || exit 1
# Stub answers a folder with rows, Recent with an empty listing, fsinfo as network.
cat > "$test_root/stub-backend" <<'PYEND'
#!/usr/bin/env python3
import json, os, sys
if "--ui-state" in sys.argv:
    sys.stdout.write("{}")
    sys.stdout.flush()
    sys.exit(0)
log_path = os.environ.get("FLEA_PICKER_REQUESTS", "")
def log(req):
    if log_path:
        with open(log_path, "a") as f:
            f.write(json.dumps(req) + "\n")
def emit(o):
    sys.stdout.write(json.dumps(o) + "\n")
    sys.stdout.flush()
rows = [{"n": "photo%d.jpg" % i, "d": False, "s": 20480, "m": 1758835200, "p": 33188, "i": "image-x-generic", "t": True, "k": 0} for i in range(60)]
for line in sys.stdin:
    try:
        req = json.loads(line)
    except ValueError:
        continue
    log(req)
    kind = req.get("c")
    if kind == "list":
        emit({"t": "listed", "n": 60, "read": 1.0, "sort": 1.0, "v": 1, "w": True, "path": req.get("path", "")})
        emit({"t": "rows", "start": 0, "rows": rows, "ms": 1.0, "kinds": []})
    elif kind == "listpaths":
        emit({"t": "listed", "n": 0, "read": 1.0, "sort": 1.0, "v": 1, "w": True, "path": "flea:recent"})
    elif kind == "fsinfo":
        emit({"t": "fsinfo", "fs": "tmpfs", "free": 123, "path": "/winprobe", "class": "network"})
    elif kind == "quit":
        break
PYEND
chmod +x "$test_root/stub-backend" || exit 1
probe_timeout=30
output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    FLEA_BIN="$test_root/stub-backend" FLEA_PICKER_REQUESTS="$test_root/requests" \
    FLEA_PICKER='{"mode":"open","title":"grid probe","folder":"/winprobe"}' FLEA_PICKER_REPLY="$test_root/reply.json" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout "$probe_timeout" qs -p "$test_root/config" 2>&1)
# Sample input, one probe line: 'PICKERGRID PASS screen=0..19 scrolled<=39 hidden=60 fsinfo="network"'.
pass_count=$(printf '%s\n' "$output" | grep -c 'PICKERGRID PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'PICKERGRID FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the picker grid asked outside its visible tiles, or the window never chained fsinfo to thumb\n'
    printf '%s\n' "$output" | grep -a 'PICKERGRID'
    printf '%s\n' "$output" | grep -aiE 'ERROR|error' | head -5
    printf '%s\n' "$output" | tail -5
    exit 1
fi
want_fsinfo=1
fsinfo_count=$(grep -c '"c": "fsinfo"' "$test_root/requests" || true)
if [ "$fsinfo_count" -ne "$want_fsinfo" ]; then
    printf 'FAIL want 1 fsinfo ask (folder only, Recent asks none), got %s\n' "$fsinfo_count"
    cat "$test_root/requests"
    exit 1
fi
thumb_lines=$(grep '"c": "thumb"' "$test_root/requests" || true)
if [ -z "$thumb_lines" ]; then
    printf 'FAIL no thumb ask followed the fsinfo answer\n'
    cat "$test_root/requests"
    exit 1
fi
if ! printf '%s\n' "$thumb_lines" | grep -q '"cacheOnly": true'; then
    printf 'FAIL the network thumb ask was not cache-only\n'
    printf '%s\n' "$thumb_lines"
    exit 1
fi
fsinfo_at=$(grep -n -m1 '"c": "fsinfo"' "$test_root/requests" | cut -d: -f1)
thumb_at=$(grep -n -m1 '"c": "thumb"' "$test_root/requests" | cut -d: -f1)
if [ "$thumb_at" -le "$fsinfo_at" ]; then
    printf 'FAIL thumb ask landed before the fsinfo answer\n'
    cat "$test_root/requests"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'PICKERGRID PASS.*'
