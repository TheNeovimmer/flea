#!/usr/bin/env bash
# TallPreviews callout 7 is scheduled for 0.3.10; prove its only red leg is the unchanged scroll-restoration assertion.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-preview-040.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER"
trap 'sandbox_remove "$test_root"' EXIT
mkdir -p "$test_root/config" "$test_root/fixture" "$test_root"/{home,state,cache,data,runtime,tmp}
chmod 700 "$test_root/runtime"
ln -s "$PWD/ui" "$test_root/config/flea"
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons"
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui"
cp tests/preview-040.qml "$test_root/config/shell.qml"
python3 - "$test_root/fixture" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
for name in ('a', 'b'):
    (root / (name + '.md')).write_text('\n\n'.join(f'{name} paragraph {i}.' for i in range(100)))
PY
output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_CACHE_HOME="$test_root/cache" XDG_DATA_HOME="$test_root/data" XDG_RUNTIME_DIR="$test_root/runtime" TMPDIR="$test_root/tmp" \
    FLEA_BIN="$PWD/target/debug/flea" FLEA_PREVIEW_040_DIR="$test_root/fixture" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    timeout 15 qs -p "$test_root/config" 2>&1)
code=$?
printf '%s\n' "$output" | sed -n '/PREVIEW_040/p'
warnings=$(printf '%s\n' "$output" | grep -E 'TypeError|ReferenceError|Unable to assign' || true)
if [ -n "$warnings" ]; then
    printf 'FAIL preview binding warning: %s\n' "$warnings"
    exit 1
fi
# Only the exact known red leg is accepted; a timeout, missing check, extra failure or unexpected green fails this gate.
if ! printf '%s\n' "$output" | python3 -c '
import re, sys
output = sys.stdin.read()
checks = re.findall(r"PREVIEW_040 (PASS|FAIL) ([^\n]+)", output)
failed = [label for verdict, label in checks if verdict == "FAIL"]
sys.exit(0 if len(checks) == 4 and len(failed) == 1
    and re.fullmatch(r"revisiting A restores A scroll got=-?\d+ expected=120", failed[0])
    and output.count("PREVIEW_040 DONE 4 checks, 1 failed") == 1 else 1)
' || [ "$code" -ne 1 ]; then
    printf 'FAIL preview-040 did not produce exactly its expected red leg (exit=%s)\n' "$code"
    printf '%s\n' "$output" | tail -8
    exit 1
fi
printf 'preview-040: 4 checks, 1 expected failure, 0 unexpected failures\n'
