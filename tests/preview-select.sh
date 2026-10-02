#!/usr/bin/env bash
# A selection change that keeps the cursor reloads the preview column, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
# qs exits 128 + SIGTERM when the probe kills itself after its receipt.
self_kill_exit=143
# PASS lines tests/preview-select.qml prints on a clean run.
expected=6

if ! command -v qs >/dev/null; then
    echo "preview-select.sh: qs is not installed, cannot drive the preview"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-preview-select.XXXXXX") || exit 1
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
cp tests/preview-select.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input: "  INFO qml: PREVIEWSELECT PASS settled single loads" and "  INFO qml: PREVIEWSELECT DONE failures=0".
pass_count=$(printf '%s\n' "$output" | grep -c 'PREVIEWSELECT PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'PREVIEWSELECT FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'PREVIEWSELECT DONE')
verdict=0
if [ "$qs_status" -ne "$self_kill_exit" ]; then
    printf 'FAIL qs exited %s, want the owned self-kill %s after DONE\n' "$qs_status" "$self_kill_exit"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE beside the PASS\n' "$done_count"
    verdict=1
fi
if [ "$pass_count" -ne "$expected" ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a selection change kept the old preview, or a lone bump reloaded\n'
    printf '%s\n' "$output" | grep -aE 'PREVIEWSELECT|ERROR|error'
    verdict=1
fi
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR')
if [ -n "$warnings" ]; then
    printf 'FAIL the preview harness logged a warning\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'PREVIEWSELECT PASS.*'
printf 'PREVIEWSELECT STATUS qs_exit=%s done=1\n' "$qs_status"
