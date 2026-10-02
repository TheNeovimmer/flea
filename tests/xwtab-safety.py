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
    block = probe[probe.index('    if layerdrop_path_matches "$seen" "$lifted_path"; then'):]
    check('catcher outcome never masquerades as fixture PANEL-DROP PASS', 'out "PASS"' not in block)

print(f'{checks} safety checks, {failures} failed')
raise SystemExit(bool(failures))
