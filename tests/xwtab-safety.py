#!/usr/bin/env python3
# Run shipped shell helpers against owned-window, receiver, and trace doubles.
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
UI = (ROOT / 'tests/ui.sh').read_text()
checks = 0
failures = 0


def check(name, condition, detail=''):
    global checks, failures
    checks += 1
    if condition:
        print('ok ' + name)
    else:
        failures += 1
        print('FAIL ' + name + ': ' + detail)


# Sample input: "xwtab_release() {\n    ydotool click 0x80\n}".
def function(text, name):
    start = text.index(name + '() {')
    line = text[start:text.index('\n', start)]
    if line.endswith('}'): return line
    return text[start:text.index('\n}', start) + 2]



def shell(code):
    return subprocess.run(['bash', '-c', code], cwd=ROOT, capture_output=True, text=True, timeout=10)


with tempfile.TemporaryDirectory() as temporary:
    scratch = pathlib.Path(temporary)
    log = scratch / 'calls'
    result = shell(function(UI, 'xwtab_cleanup') + f'''
recv_pid=345
xwtab_release() {{ :; }}
xwtab_restore_place() {{ :; }}
kill() {{ printf '%s\\n' "$*" >> '{log}'; }}
wait() {{ :; }}
xwtab_cleanup
''')
    check('failure cleanup kills saved receiver pid', result.returncode == 0 and log.exists() and '345' in log.read_text(), result.stdout + result.stderr)

    room_helpers = UI[UI.index('xwtab_rect_of() {'):UI.index('# xw6: a tab dragged onto another Flea')]
    double = f'''
repo='{ROOT}'
xwtab_saved=''
xwtab_cleanup() {{ :; }}
fail() {{ echo "FAIL $*"; exit 1; }}
flea_process_owned() {{ [[ "$1" == 101 || "$1" == 202 ]]; }}
sleep() {{ :; }}
hyprctl() {{
    if [[ "$1" == monitors ]]; then
        printf '%s\\n' '[{{"name":"DP-2","x":0,"y":0,"width":1000,"height":800,"focused":true,"activeWorkspace":{{"id":1}}}}]'
    elif [[ "$1" == clients ]]; then printf '[]\\n'
    elif [[ "$1" == layers ]]; then printf '{{}}\\n'
    elif [[ "$1" == dispatch ]]; then
        printf '%s\\n' "$2" >> '{log}'
    fi
}}
xwtab_rect_of() {{
    local addr x y w h
    if [[ "$1" == 101 ]]; then addr=0xa; x=20; else addr=0xb; x=510; fi
    y=20; w=470; h=370
    if [[ "${{stale:-false}}" == true || ! -s '{log}' ]]; then x=0; y=0; w=900; h=500; fi
    printf '%s %s %s %s %s True\\n' "$addr" "$x" "$y" "$w" "$h"
}}
'''
    result = shell(room_helpers + double + '\nxwtab_make_room 101 202\n')
    calls = log.read_text() if log.exists() else ''
    actions = [line for line in calls.splitlines() if 'hl.dsp.window.' in line]
    check('room operations target owned addresses despite ignored focus', result.returncode == 0 and len(actions) >= 4 and all('window = "address:' in line for line in actions), calls + result.stderr)
    result = shell(room_helpers + double + '\nstale=true\nxwtab_make_room 101 202\n')
    check('room fails when geometry never moved', result.returncode != 0, result.stdout + result.stderr)

    log.write_text('')
    result = shell(room_helpers + double + '''
xwtab_saved='101 0xa 20 20 470 370 False
999 0xforeign 1 2 3 4 True'
xwtab_restore_place
''')
    calls = log.read_text()
    actions = [line for line in calls.splitlines() if 'hl.dsp.window.' in line]
    check('restore touches only proven owned address', actions and all('window = "address:0xa"' in line for line in actions), calls + result.stderr)

    centered = r'''
declare -A state_x=([101]=40 [202]=1100)
declare -A state_y=([101]=80 [202]=80)
declare -A state_w=([101]=1000 [202]=1000)
declare -A state_h=([101]=720 [202]=720)
xwtab_rect_of() {
    local pid="$1" addr=0xa
    [[ "$pid" != 202 ]] || addr=0xb
    printf '%s %s %s %s %s True\n' "$addr" "${state_x[$pid]}" "${state_y[$pid]}" "${state_w[$pid]}" "${state_h[$pid]}"
}
hyprctl() {
    local pid=101 coords nx ny
    case "$1" in
        monitors)
            printf '%s\n' '[{"name":"DP-2","x":0,"y":0,"width":2560,"height":1440,"focused":true,"activeWorkspace":{"id":1}}]'
            return 0
            ;;
        clients)
            printf '[]\n'
            return 0
            ;;
        layers)
            printf '{}\n'
            return 0
            ;;
    esac
    [[ "$2" != *address:0xb* ]] || pid=202
    [[ "$2" != *window.float* ]] || return 0
    # Sample input: hl.dsp.window.resize({ x = 1250, y = 690, relative = false, window = "address:0xa" }).
    coords=${2#*x = }
    coords=${coords%%, relative*}
    coords=${coords/, y = / }
    read -r nx ny <<< "$coords"
    if [[ "$2" == *window.resize* ]]; then
        state_x[$pid]=$((state_x[$pid] + (state_w[$pid] - nx) / 2))
        state_y[$pid]=$((state_y[$pid] + (state_h[$pid] - ny) / 2))
        state_w[$pid]=$nx
        state_h[$pid]=$ny
    else
        state_x[$pid]=$nx
        state_y[$pid]=$ny
    fi
}
'''
    result = shell(room_helpers + double + centered + '\nxwtab_make_room 101 202\nxwtab_rect_of 101\n')
    check('room reaches exact parked rectangle with centered resize', result.returncode == 0 and '0xa 20 20 1250 690 True' in result.stdout, result.stdout + result.stderr)
    result = shell(room_helpers + double + centered + '''
state_x[101]=20
state_y[101]=20
state_w[101]=1250
state_h[101]=690
xwtab_saved='101 0xa 40 80 1000 720 True'
xwtab_restore_place
status=$?
xwtab_rect_of 101
exit "$status"
''')
    check('restore reaches exact saved rectangle with centered resize', result.returncode == 0 and '0xa 40 80 1000 720 True' in result.stdout, result.stdout + result.stderr)

    restore = function(UI, 'xwtab_restore_place')
    log.write_text('')
    for failure_step in ('float-on', 'resize', 'move', 'float-off', 'readback'):
        result = shell(restore + "\nfail_at='" + failure_step + "'\n" + r'''
xwtab_saved='101 0xa 20 20 900 500 False'
flea_process_owned() { return 0; }
xwtab_rect_of() { printf '0xa 40 40 900 500 True\n'; }
hyprctl() {
    local step
    case "$2" in
        *window.float*'action = "on"'*) step=float-on ;;
        *window.float*) step=float-off ;;
        *window.resize*) step=resize ;;
        *window.move*) step=move ;;
    esac
    printf '%s\n' "$step" >> "$call_log"
    [[ "$step" != "$fail_at" ]]
}
xwtab_wait_place() {
    printf 'readback\n' >> "$call_log"
    [[ "$fail_at" != readback ]]
}
xwtab_restore_place
status=$?
printf 'status=%s saved=%s\n' "$status" "$xwtab_saved"
fail_at=none
xwtab_restore_place
printf 'retry=%s saved=%s\n' "$?" "$xwtab_saved"
exit "$status"
''' .replace('xwtab_saved=', "call_log='" + str(log) + "'\nxwtab_saved=", 1))
        calls = log.read_text().splitlines()
        expected = ['float-on', 'resize', 'move', 'float-off', 'readback']
        check('restore attempts every step after ' + failure_step + ' failure', calls[-len(expected):] == expected and calls[:len(expected)] == expected, str(calls))
        check('restore retains failed entry for retry after ' + failure_step, result.returncode != 0 and 'status=1 saved=101 0xa' in result.stdout and 'retry=0 saved=\n' in result.stdout and 'XWTAB restore failed' in result.stderr, result.stdout + result.stderr)
        log.write_text('')

    wait_cancel = function(UI, 'xwtab_wait_cancel') if 'xwtab_wait_cancel() {' in UI else ''
    start = UI.index('    key -k Escape >/dev/null', UI.index('case_xwtab()'))
    end = UI.index('    hyprctl layers -j', start)
    escape_leg = UI[start:end]
    result = shell(wait_cancel + '''
xwtab_cancel_attempts=30; xwtab_cancel_poll=0.1
xwtab_source=101; apid=101
fail() { echo "FAIL $*"; exit 1; }
key() { :; }
sleep() { :; }
xwtab_release() { released=true; }
xwtab_trace_lines() { [[ "${released:-false}" == true ]] && echo 'TABDRAG drag-finished pid=101 action=0'; }
''' + escape_leg)
    check('no-op Escape cannot pass through later release', result.returncode != 0, result.stdout + result.stderr)
    wait_call = 'xwtab_wait_cancel' if wait_cancel else 'true'
    result = shell(wait_cancel + '''
xwtab_cancel_attempts=30; xwtab_cancel_poll=0.1
xwtab_source=101
fail() { exit 1; }
sleep() { :; }
xwtab_trace_lines() { echo 'TABDRAG drag-finished pid=101 action=0'; }
''' + wait_call)
    check('cancel receipt while held satisfies Escape wait', result.returncode == 0, result.stdout + result.stderr)
    check('listing refusal requires target delivery', '"$apid" "$bpid" require' in UI[UI.index('# A drop on B\'s listing'):UI.index('# A drop onto a foreign receiver')])
    check('foreign refusal requires target delivery', '"$apid" "$recv_pid" require' in UI[UI.index('# A drop onto a foreign receiver'):UI.index("printf 'XWTAB foreign-refused")])

    scan = (ROOT / 'tests/xwtab-scan.sh').read_text()
    blocker_start = scan.index("for layer in '1 desktop-widget'")
    blocker_end = scan.index('# Keep the live shell helpers', blocker_start)
    result = shell(f"scratch='{scratch}'\nrepo='{ROOT}'\n" + '''
fail=0
ok() { printf 'ok %s\\n' "$*"; }
bad() {
    printf 'FAIL %s\\n' "$*"
    fail=$((fail + 1))
}
python3() { return 2; }
''' + scan[blocker_start:blocker_end] + '\nexit "$fail"\n')
    check('blocker assertions reject helper errors instead of empty coverage', result.returncode != 0 and result.stdout.count('scan failed (status=2)') == 4 and 'blocks desktop' not in result.stdout, result.stdout + result.stderr)

    (scratch / 'ui/boot').mkdir(parents=True)
    (scratch / 'tests').symlink_to(ROOT / 'tests', target_is_directory=True)
    (scratch / 'ui/boot/bad.qml').write_text('PanelWindow { Keys.onPressed: function(event) {} Item { focus: true } }')
    boot = (ROOT / 'tests/bootload.sh').read_text()
    validation = boot[boot.index('# Keys on a PanelWindow'):boot.index('output=$(env')]
    result = shell("cd '" + str(scratch) + "'\nfiles=bad.qml\n" + validation)
    check('unrelated focus never exempts PanelWindow Keys', result.returncode != 0, result.stdout + result.stderr)

    (scratch / 'ui/boot/good.qml').write_text('PanelWindow { Item { Keys.onPressed: function(event) {} focus: true } }')
    result = shell("cd '" + str(scratch) + "'\nfiles=good.qml\n" + validation)
    check('Keys on their own focused Item remain valid', result.returncode == 0, result.stdout + result.stderr)

    probe = (ROOT / 'tests/probes/layer-drop-bottom.sh').read_text()
    gesture_start = probe.index('move_to "$sx" "$sy"\ndrag_mark=')
    gesture_end = probe.index('# Wait for an observed panel receipt', gesture_start)
    gesture = probe[gesture_start:gesture_end]
    waits = function(probe, 'layerdrop_wait_drag') if 'layerdrop_wait_drag() {' in probe else ''
    log.write_text('')
    result = shell(waits + f"\nwork='{scratch}'\ncall_log='{log}'\n" + r'''
sx=348
sy=81
wx=40
wy=40
ww=900
wh=500
dx=8
dy=1432
flea_pid=101
srcdir=/fixture
layerdrop_outside_x=200
layerdrop_outside_y=60
layerdrop_target_nudge=6
layerdrop_drag_attempts=40
layerdrop_drag_poll=0.1
layerdrop_button_down=false
pressed=false
motions=0
refuse() {
    echo "FAIL $*"
    exit 1
}
sleep() { :; }
hyprctl() { printf '%s\n' '{"DP-2": {"levels": {"1": [{"namespace": "flea-tab-tearoff"}]}}}'; }
move_to() {
    printf 'motion %s %s\n' "$1" "$2" >> "$call_log"
    [[ "$pressed" == true ]] || return 0
    motions=$((motions + 1))
    if [[ "$motions" == 1 ]]; then
        printf 'TABDRAG drag-start pid=101 path=/fixture mime=application/x-flea-tab\n' >> "$work/flea.log"
    else
        printf 'TABDRAG catcher-enter pid=101 global=%s,%s\n' "$1" "$2" >> "$work/flea.log"
    fi
}
ydotool() {
    if [[ "$2" == 0x40 ]]; then
        pressed=true
        printf 'press\n' >> "$call_log"
    else
        printf 'release\n' >> "$call_log"
        grep -q catcher-enter "$work/flea.log" || return 1
    fi
}
''' + gesture)
    expected = ['motion 348 81', 'press', 'motion 240 600', 'motion 8 1432', 'motion 14 1432', 'motion 8 1432', 'release']
    check('layer probe waits for catcher after platform start before release', result.returncode == 0 and log.read_text().splitlines() == expected, result.stdout + result.stderr + log.read_text())
    for trace in ('TABDRAG drag-start pid=101 path=/fixture mime=application/x-flea-tab\nTABDRAG drag-finished pid=101 action=0\n', 'TABDRAG drag-start pid=101 path=/fixture mime=application/x-flea-tab\n'):
        (scratch / 'flea.log').write_text(trace)
        result = shell(waits + f"\nwork='{scratch}'\n" + '''
flea_pid=101
srcdir=/fixture
drag_mark=0
layerdrop_drag_attempts=2
layerdrop_drag_poll=0.1
refuse() {
    echo "FAIL $*"
    exit 1
}
sleep() { :; }
layerdrop_wait_drag catcher
''')
        check('layer probe refuses release without a held catcher receipt', result.returncode != 0, result.stdout + result.stderr)
    block = probe[probe.index('    if layerdrop_path_matches "$seen" "$lifted_path"; then'):]
    check('catcher outcome never masquerades as fixture PANEL-DROP PASS', 'out "PASS"' not in block)

print(f'{checks} safety checks, {failures} failed')
raise SystemExit(bool(failures))
