#!/bin/bash
# Drives the shipped receiver's pane binding and deadline without waiting for wall-clock time.
set -u
cd "$(dirname "$0")/.." || exit 1
probe_seconds=15
output=$(env QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout "$probe_seconds" qml6 tests/tabreceive.qml 2>&1)
status=$?
printf '%s\n' "$output"
if [ "$status" -ne 0 ]; then
    exit "$status"
fi
# Sample input: "qml: tabreceive: 32 checks, 0 failed".
grep -qE 'tabreceive: [1-9][0-9]* checks, 0 failed$' <<< "$output"
