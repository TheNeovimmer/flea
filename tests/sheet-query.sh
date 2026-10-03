#!/usr/bin/env bash
# The real KeymapSheet over a stub pane draws CommandPalette's query states, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "sheet-query.sh: qs is not installed, cannot build the sheet"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-sheetquery.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/sheet-query.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input: "  INFO qml: SHEETQUERY PASS checks=18" then "  INFO qml: SHEETQUERY DONE failures=0".
# The owned termination is the probe's own self-kill (SIGTERM, 143) after its one DONE receipt.
pass_count=$(printf '%s\n' "$output" | grep -c 'SHEETQUERY PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'SHEETQUERY FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'SHEETQUERY DONE')
verdict=0
if [ "$qs_status" -ne 143 ]; then
    printf 'FAIL qs exited %s, want the owned self-kill 143 after DONE\n' "$qs_status"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE beside the PASS\n' "$done_count"
    verdict=1
fi
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the sheet missed one of CommandPalette query states\n'
    printf '%s\n' "$output" | grep -aE 'SHEETQUERY|ERROR|error'
    verdict=1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the sheet's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the sheet harness logged a warning\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'SHEETQUERY PASS.*'
printf 'SHEETQUERY STATUS qs_exit=%s done=1\n' "$qs_status"
