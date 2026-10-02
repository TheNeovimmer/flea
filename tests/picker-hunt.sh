#!/usr/bin/env bash
# Release hunt: board behavior through real picker keys and backend responses.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-picker-hunt.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER"
trap 'sandbox_remove "$test_root"' EXIT
mkdir -p "$test_root/config" "$test_root/fixture"
ln -s "$PWD/ui" "$test_root/config/flea"
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons"
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui"
cp tests/picker-hunt.qml "$test_root/config/shell.qml"
for name in {a..l}; do printf '%s\n' "$name" > "$test_root/fixture/$name.txt"; done
failures=0
phases=0
for view in list grid; do
    for scenario in control marked-open remember cursor-open all range path save-marks collision; do
        phase="$test_root/$view-$scenario"
        mkdir -p "$phase"/{home,state/flea,cache,data,runtime,tmp}
        chmod 700 "$phase/runtime"
        mode=open
        multiple=true
        preset=default
        case "$scenario" in cursor-open|marked-open) multiple=false; preset=mac ;; esac
        case "$scenario" in save-marks|collision) mode=save; multiple=false ;; esac
        printf '{"pickerView":"%s","keys":"%s"}' "$view" "$preset" > "$phase/state/flea/ui.json"
        request=$(python3 - "$mode" "$multiple" "$test_root/fixture" <<'PY'
import json,sys
print(json.dumps(dict(mode=sys.argv[1],multiple=sys.argv[2]=='true',folder=sys.argv[3],name='a.txt',title='Picker hunt')))
PY
        )
        output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
            HOME="$phase/home" XDG_STATE_HOME="$phase/state" XDG_CONFIG_HOME="$phase/home/.config" \
            XDG_CACHE_HOME="$phase/cache" XDG_DATA_HOME="$phase/data" XDG_RUNTIME_DIR="$phase/runtime" TMPDIR="$phase/tmp" \
            FLEA_BIN="$PWD/target/debug/flea" FLEA_PICKER="$request" FLEA_PICKER_REPLY="$phase/reply.json" \
            FLEA_PICKER_HUNT_CASE="$scenario" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
            QT_FORCE_STDERR_LOGGING=1 timeout 15 qs -p "$test_root/config" 2>&1)
        code=$?
        phases=$((phases+1))
        printf 'PICKER_HUNT CASE %s %s exit=%s\n' "$view" "$scenario" "$code"
        printf '%s\n' "$output" | sed -n '/PICKER_HUNT/p'
        if printf '%s\n' "$output" | grep -q 'PICKER_HUNT FAIL'; then
            failures=$((failures+1))
        elif [ "$scenario" = cursor-open ] || [ "$scenario" = marked-open ]; then
            if ! python3 - "$phase/reply.json" <<'PY'
import json,sys
try:r=json.load(open(sys.argv[1]))
except (OSError,ValueError):sys.exit(1)
sys.exit(0 if r.get('response')==0 and len(r.get('uris',[]))==1 else 1)
PY
            then echo 'FAIL file activation did not write a successful portal reply'; failures=$((failures+1)); fi
        elif ! printf '%s\n' "$output" | grep -q 'PICKER_HUNT DONE.*0 failed'; then
            echo 'FAIL picker hunt did not reach a clean verdict'
            printf '%s\n' "$output" | tail -8
            failures=$((failures+1))
        fi
        if [ "$scenario" = remember ]; then
            wanted=grid
            [ "$view" = grid ] && wanted=list
            if ! python3 - "$phase/state/flea/ui.json" "$wanted" <<'PY'
import json,sys
try:r=json.load(open(sys.argv[1]))
except (OSError,ValueError):sys.exit(1)
sys.exit(0 if r.get('pickerView')==sys.argv[2] else 1)
PY
            then echo 'FAIL remembered view was not persisted for restart'; failures=$((failures+1)); fi
        fi
        warnings=$(printf '%s\n' "$output" | grep -E 'TypeError|ReferenceError|Unable to assign' || true)
        if [ -n "$warnings" ]; then printf 'FAIL picker binding warning: %s\n' "$warnings"; failures=$((failures+1)); fi
    done
done
printf 'picker-hunt: %s phases, %s failed\n' "$phases" "$failures"
[ "$failures" -eq 0 ]
