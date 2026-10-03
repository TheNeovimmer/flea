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
cp -a ui "$test_root/config/flea"
# The probe exits normally after the same saved reply and two worker exits that end the real chooser.
python3 - "$test_root/config/flea/PickerWindow.qml" <<'PYCODE'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
# Sample input: onStopped: Quickshell.execDetached(["kill", String(Quickshell.processId)])
stopped = 'onStopped: Quickshell.execDetached(["kill", String(Quickshell.processId)])'
if source.count(stopped) != 1:
    sys.exit("FAIL picker hunt could not identify the owned teardown")
path.write_text(source.replace(stopped, 'onStopped: Qt.exit(0)'))
PYCODE
[ "$?" -eq 0 ] || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons"
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui"
cp tests/picker-hunt.qml "$test_root/config/shell.qml"
cp tests/picker-focus-helper.py "$test_root/focus-backend"
chmod +x "$test_root/focus-backend"
for name in {a..l}; do printf '%s\n' "$name" > "$test_root/fixture/$name.txt"; done
failures=0
phases=0
burst_extra_files=64
for preset in default mac vim windows; do
for view in list grid; do
    for scenario in control marked-open marked-enter remember cursor-open cursor-enter cursor-multi cursor-button double-mark all all-wide range range-up range-click range-burst range-shrink save-marks single-marks folder empty refuse-mark refuse-button refuse-validate refuse-review refuse-moved refuse-returned refuse-cancel refuse-collision; do
        if [[ "$scenario" = refuse-* && "$preset" != default ]]; then continue; fi
        if [ "$preset" = vim ] || [ "$preset" = windows ]; then
            case "$scenario" in cursor-open|cursor-enter|marked-open|marked-enter) ;; *) continue ;; esac
        fi
        phase="$test_root/$preset-$view-$scenario"
        mkdir -p "$phase"/{home,state/flea,cache,data,runtime,tmp}
        chmod 700 "$phase/runtime"
        mode=open
        multiple=true
        case "$scenario" in cursor-open|cursor-enter|cursor-button|single-marks) multiple=false ;; esac
        case "$scenario" in save-marks) mode=save; multiple=false ;; esac
        case "$scenario" in refuse-*) multiple=false ;; esac
        case "$scenario" in refuse-review|refuse-collision) mode=save ;; esac
        backend="$PWD/target/debug/flea"
        case "$scenario" in refuse-*) backend="$test_root/focus-backend" ;; esac
        printf '{"pickerView":"%s","keys":"%s"}' "$view" "$preset" > "$phase/state/flea/ui.json"
        fixture="$test_root/fixture"
        case "$scenario" in
            range-burst)
                fixture="$phase/fixture"
                mkdir -p "$fixture"
                cp "$test_root/fixture/"*.txt "$fixture/"
                for i in $(seq 1 "$burst_extra_files"); do printf '%s\n' "$i" > "$fixture/z-extra-$i.txt"; done
                ;;
            all-wide)
                fixture="$phase/fixture"
                mkdir -p "$fixture/folder"
                cp "$test_root/fixture/"*.txt "$fixture/"
                for i in $(seq 0 199); do printf '%s\n' "$i" > "$fixture/extra-$i.txt"; done
                printf 'hidden\n' > "$fixture/.hidden.txt"
                printf 'filtered\n' > "$fixture/excluded.png"
                ;;
            folder|empty)
                fixture="$phase/fixture"
                mkdir -p "$fixture"
                if [ "$scenario" = folder ]; then mkdir "$fixture/z-folder"; printf 'child\n' > "$fixture/z-folder/child.txt"; fi
                ;;
        esac
        request=$(python3 - "$mode" "$multiple" "$fixture" "$scenario" <<'PY'
import json,sys
request=dict(mode=sys.argv[1],multiple=sys.argv[2]=='true',folder=sys.argv[3],name='a.txt',title='Picker hunt')
if sys.argv[4]=='all-wide':request['filters']=[dict(label='Text',globs=['*.txt'],mimes=[])]
if sys.argv[4].startswith('refuse-'):request['filters']=[dict(label='Text',globs=['*.txt'],mimes=[])]
print(json.dumps(request))
PY
        )
        output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
            HOME="$phase/home" XDG_STATE_HOME="$phase/state" XDG_CONFIG_HOME="$phase/home/.config" \
            XDG_CACHE_HOME="$phase/cache" XDG_DATA_HOME="$phase/data" XDG_RUNTIME_DIR="$phase/runtime" TMPDIR="$phase/tmp" \
            FLEA_BIN="$backend" FLEA_PICKER="$request" FLEA_PICKER_REPLY="$phase/reply.json" \
            FLEA_PICKER_HUNT_CASE="$scenario" FLEA_PICKER_HUNT_PRESET="$preset" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
            QT_FORCE_STDERR_LOGGING=1 timeout 15 qs -p "$test_root/config" 2>&1)
        code=$?
        phases=$((phases+1))
        printf 'PICKER_HUNT CASE %s %s %s exit=%s\n' "$preset" "$view" "$scenario" "$code"
        printf '%s\n' "$output" | sed -n '/PICKER_HUNT/p'
        if [ "$code" -ne 0 ]; then
            printf 'FAIL picker phase %s %s %s exit=%s\n' "${preset:-default}" "$view" "$scenario" "$code"
            failures=$((failures+1))
        elif grep -q 'PICKER_HUNT FAIL' <<< "$output"; then
            failures=$((failures+1))
        elif [[ "$scenario" = cursor-* || "$scenario" = marked-* || "$scenario" = refuse-* && "$scenario" != refuse-collision ]]; then
            if ! python3 - "$phase/reply.json" "$fixture" "$scenario" <<'PY'
import json,sys
try:r=json.load(open(sys.argv[1]))
except (OSError,ValueError):sys.exit(1)
from pathlib import Path
chosen='b.txt' if sys.argv[3].startswith('marked-') else 'a.txt'
if sys.argv[3]=='refuse-cancel':sys.exit(0 if r=={'response':1} else 1)
sys.exit(0 if r.get('response')==0 and r.get('uris')==[(Path(sys.argv[2])/chosen).as_uri()] else 1)
PY
            then echo 'FAIL file activation did not write a successful portal reply'; failures=$((failures+1)); fi
        elif ! grep -q 'PICKER_HUNT DONE.*0 failed' <<< "$output"; then
            echo 'FAIL picker hunt did not reach a clean verdict'
            printf '%s\n' "$output" | tail -8
            failures=$((failures+1))
        fi
        if [ "$scenario" = double-mark ] && [ -e "$phase/reply.json" ]; then
            echo 'FAIL marking double clicks wrote a portal reply'
            failures=$((failures+1))
        fi
        if [[ "$scenario" = refuse-* ]] && ! grep -q 'PICKER_HUNT DONE.*0 failed' <<< "$output"; then
            echo 'FAIL focus refusal probe did not reach a clean verdict'
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
        warnings=$(printf '%s\n' "$output" | grep -E 'TypeError|ReferenceError|Unable to assign|Cannot anchor to an item' || true)
        if [ -n "$warnings" ]; then printf 'FAIL picker binding warning: %s\n' "$warnings"; failures=$((failures+1)); fi
    done
done
done
printf 'picker-hunt: %s phases, %s failed\n' "$phases" "$failures"
[ "$failures" -eq 0 ]
