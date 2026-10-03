#!/usr/bin/env bash
# Exercise retained picker identities and batch selection in the suite's isolated test sandbox.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/picker-native-lock-check.py
python3 tests/picker-runner-check.py
cargo test --locked backend::picker::tests -- --test-threads=1

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/selection/js"
cp ui/PickerSelection.qml "$scratch/selection/"
cp ui/js/*.js "$scratch/selection/js/"
cp tests/picker-selection.qml "$scratch/"
status=0
output=$(env QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 QT_FORCE_STDERR_LOGGING=1 timeout 15 qml6 "$scratch/picker-selection.qml" 2>&1) || status=$?
printf '%s\n' "$output"
if [ "$status" -ne 0 ]; then
    exit "$status"
fi
grep -q 'picker-selection QML: .* checks, 0 failed' <<< "$output"
