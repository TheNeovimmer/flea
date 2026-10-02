#!/usr/bin/env bash
# Real rendered Markdown and Quick Look scroll behavior against the release boards.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-preview-hunt.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER"
trap 'sandbox_remove "$test_root"' EXIT
mkdir -p "$test_root/config" "$test_root/fixture"
ln -s "$PWD/ui" "$test_root/config/flea"
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons"
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui"
cp tests/preview-hunt.qml "$test_root/config/shell.qml"
printf 'Hello preview.\n' > "$test_root/fixture/control.md"
printf '%s\n' '- [ ] todo' '- [x] done' > "$test_root/fixture/tasks.md"
printf '%s\n' 'Read [guide][g].' '' '```' 'code' '```' '' '[g]: https://example.com/guide' > "$test_root/fixture/reference.md"
printf '%s\n' '| Name |' '| --- |' '| **bold** |' > "$test_root/fixture/table.md"
python3 - "$test_root/fixture" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1])
for name in ('a','b'):
 (root/(name+'.md')).write_text('\n\n'.join(f'{name} paragraph {i}.' for i in range(100)))
PY
failures=0
for scenario in control tasks reference table scroll source-key; do
    phase="$test_root/$scenario"
    mkdir -p "$phase"/{home,state,cache,data,runtime,tmp}
    chmod 700 "$phase/runtime"
    output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$phase/home" XDG_STATE_HOME="$phase/state" XDG_CONFIG_HOME="$phase/home/.config" \
        XDG_CACHE_HOME="$phase/cache" XDG_DATA_HOME="$phase/data" XDG_RUNTIME_DIR="$phase/runtime" TMPDIR="$phase/tmp" \
        FLEA_BIN="$PWD/target/debug/flea" FLEA_PREVIEW_HUNT_CASE="$scenario" FLEA_PREVIEW_HUNT_DIR="$test_root/fixture" \
        QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        timeout 15 qs -p "$test_root/config" 2>&1)
    code=$?
    printf 'PREVIEW_HUNT CASE %s exit=%s\n' "$scenario" "$code"
    printf '%s\n' "$output" | sed -n '/PREVIEW_HUNT/p'
    if [ "$code" -ne 0 ] || ! printf '%s\n' "$output" | grep -q 'PREVIEW_HUNT DONE.*0 failed'; then
        failures=$((failures+1))
        if ! printf '%s\n' "$output" | grep -q 'PREVIEW_HUNT DONE'; then
            echo 'FAIL preview hunt did not complete'
            printf '%s\n' "$output" | tail -8
        fi
    fi
    warnings=$(printf '%s\n' "$output" | grep -E 'TypeError|ReferenceError|Unable to assign' || true)
    if [ -n "$warnings" ]; then printf 'FAIL preview binding warning: %s\n' "$warnings"; failures=$((failures+1)); fi
    if [ "$scenario" = source-key ]; then
        if ! python3 - "$phase/state/flea/ui.json" <<'PY'
import json,sys
try:r=json.load(open(sys.argv[1]))
except (OSError,ValueError):sys.exit(1)
sys.exit(0 if r.get('preview',{}).get('markdownView')=='source' else 1)
PY
        then echo 'FAIL Source choice was not persisted for restart'; failures=$((failures+1)); fi
    fi
done
printf 'preview-hunt: 6 phases, %s failed\n' "$failures"
[ "$failures" -eq 0 ]
