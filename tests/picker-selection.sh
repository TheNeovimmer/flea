#!/usr/bin/env bash
# Runs the picker lock, settle and runner checks, the backend picker tests and the selection probe in a guarded scratch root.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/picker-native-lock-check.py
python3 tests/picker-native-settle-check.py
python3 tests/picker-runner-check.py
cargo test --locked backend::picker::tests -- --test-threads=1

. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
scratch=$(mktemp -d "$SANDBOX_ROOT/flea-picker-selection.XXXXXXXX") || exit 1
: > "$scratch/$SANDBOX_MARKER"
trap 'sandbox_remove "$scratch"' EXIT
mkdir -p "$scratch/selection/js"
cp ui/PickerSelection.qml "$scratch/selection/"
cp ui/js/*.js "$scratch/selection/js/"
cp tests/picker-selection.qml "$scratch/"
status=0
probe_timeout_seconds=15
output=$(env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 QT_FORCE_STDERR_LOGGING=1 timeout "$probe_timeout_seconds" qml6 "$scratch/picker-selection.qml" 2>&1) || status=$?
printf '%s\n' "$output"
if [ "$status" -ne 0 ]; then
    exit "$status"
fi
grep -q 'picker-selection QML: .* checks, 0 failed' <<< "$output"
