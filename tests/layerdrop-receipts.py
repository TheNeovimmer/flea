#!/usr/bin/env python3
# Exercise the shipped pre-release gesture with each receiver's own hover receipt.
import ast
import json
import pathlib
import re
import shlex
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROBE = (ROOT / 'tests/probes/layer-drop-bottom.sh').read_text()
VERDICT = ROOT / 'tests/probes/layer-drop-verdict.sh'
SHELL_TIMEOUT_SECONDS = 10
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


# Sample input: layerdrop_wait_drag() {\n    local stage="$1"\n}.
def function(name):
    start = PROBE.index(name + '() {')
    return PROBE[start:PROBE.index('\n}', start) + 2]


reader = '        lines=$(tail -n +"$((drag_mark + 1))" "$work/flea.log"'
previous = PROBE[:PROBE.index(reader)].splitlines()[-1]
check('TABDRAG reader has an immediate sample-input comment',
      # Sample input: # Sample input: TABDRAG catcher-enter pid=1154634 global=1280,720
      re.fullmatch(r'\s*# Sample input: TABDRAG \S+ pid=\d+ .+', previous) is not None,
      'preceding line: ' + previous)

panel = PROBE[PROBE.index('            DropArea {'):PROBE.index('\nEOF')]
# Sample input: onEntered: function (drag) {\n                    Quickshell.execDetached(["sh", "-c", "printf 'PANEL-ENTER\\\\n' >> '$log'"])\n                }
entered = re.search(r'onEntered: function\s*\(\w+\)\s*\{(.*?)\n\s*\}', panel, re.S)
check('fixture panel logs PANEL-ENTER on entered',
      entered is not None and 'PANEL-ENTER' in entered.group(1) and '$log' in entered.group(1))

for relative in ('tests/layerdrop-receipts.py', 'tests/xwinput-safety.py'):
    source = (ROOT / relative).read_text()
    lines = source.splitlines()
    # Sample input: entered = re.search(r'onEntered: function\s*\(\w+\)\s*\{(.*?)\n\s*\}', panel, re.S)
    for node in ast.walk(ast.parse(source)):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                and isinstance(node.func.value, ast.Name) and node.func.value.id == 're'):
            continue
        comment = lines[node.lineno - 2].strip()
        check(relative + ':' + str(node.lineno) + ' regex has an immediate sample-input comment',
              comment.startswith('# Sample input: '), comment)
        if any(isinstance(argument, ast.Name) and argument.id == 'panel'
               for argument in node.args):
            check('fixture onEntered sample quotes the exact PANEL-ENTER handler',
                  entered is not None
                  and comment == '# Sample input: ' + entered.group(0).replace('\n', r'\n'),
                  comment)

gesture_start = PROBE.index('move_to "$sx" "$sy"\ndrag_mark=')
gesture_end = PROBE.index('# Wait for an observed panel receipt', gesture_start)
gesture = PROBE[gesture_start:gesture_end]

with tempfile.TemporaryDirectory() as temporary:
    scratch = pathlib.Path(temporary)
    setup = '\n'.join(('work=' + shlex.quote(str(scratch)),
                       'log="$work/panel.log"',
                       '. ' + shlex.quote(str(VERDICT))))
    panel_start = PROBE.index('cat > "$work/panel.qml" <<EOF')
    panel_end = PROBE.index('\nEOF', panel_start) + len('\nEOF')
    result = subprocess.run(['bash', '-uc', setup + '\n' + PROBE[panel_start:panel_end]],
                            capture_output=True, text=True, timeout=SHELL_TIMEOUT_SECONDS)
    generated = (scratch / 'panel.qml').read_text()
    # Sample input: onEntered: function (drag) {\n                    Quickshell.execDetached(["sh", "-c", "printf 'PANEL-ENTER\\n' >> '/fixture/panel.log'"])\n                }
    handler = re.search(r'onEntered: function\s*\(\w+\)\s*\{(.*?)\n\s*\}', generated, re.S)
    # Sample input: Quickshell.execDetached(["sh", "-c", "printf 'PANEL-ENTER\\n' >> '/fixture/panel.log'"])
    command = re.search(r'Quickshell\.execDetached\((\[.*\])\)', handler.group(1)) if handler else None
    if command:
        # Sample input: ["sh", "-c", "printf 'PANEL-ENTER\\n' >> '/fixture/panel.log'"]
        result = subprocess.run(json.loads(command.group(1)), capture_output=True, text=True,
                                timeout=SHELL_TIMEOUT_SECONDS)
    check('generated panel enter command writes the exact hover receipt',
          command is not None and result.returncode == 0
          and (scratch / 'panel.log').read_text() == 'PANEL-ENTER\n')
    doubles = r'''
sx=348
sy=81
wx=40
wy=40
wh=500
dx=8
dy=1432
flea_pid=101
srcdir=/fixture
layerdrop_outside_x=200
layerdrop_outside_y=60
layerdrop_target_nudge=6
layerdrop_drag_attempts=2
layerdrop_drag_poll=0
pressed=false
motions=0
refuse() {
    printf 'REFUSED %s\n' "$*"
    exit 1
}
sleep() { :; }
hyprctl() {
    [[ "$route" != unmapped ]] || return 0
    printf '%s\n' '{"levels":{"1":[{"namespace": "flea-tab-tearoff"}]}}'
}
move_to() {
    [[ "$pressed" == true ]] || return 0
    motions=$((motions + 1))
    if [[ "$motions" == 1 ]]; then
        printf 'TABDRAG drag-start pid=101 path=/fixture mime=application/x-flea-tab\n' >> "$work/flea.log"
    elif [[ "$route" == catcher || "$route" == unmapped ]]; then
        printf 'TABDRAG catcher-enter pid=101 global=8,1432\n' >> "$work/flea.log"
    elif [[ "$route" == panel || "$route" == finished ]]; then
        printf 'PANEL-ENTER\n' >> "$log"
    fi
    if [[ "$route" == finished ]]; then
        printf 'TABDRAG drag-finished pid=101 action=0\n' >> "$work/flea.log"
    fi
}
ydotool() {
    if [[ "$2" == 0x40 ]]; then
        pressed=true
    else
        printf 'release\n' >> "$work/releases"
        if [[ "$route" == panel ]]; then
            printf 'PANEL-DROP\n' >> "$log"
        else
            printf 'CATCHER-TEAROFF\n' >> "$work/catcher"
        fi
    fi
}
'''
    for route in ('panel', 'catcher', 'missing', 'finished', 'unmapped'):
        for name in ('flea.log', 'panel.log', 'releases', 'catcher'):
            (scratch / name).write_text('')
        code = function('layerdrop_wait_drag') + '\n' + setup + '\n' + doubles
        code += '\nroute=' + route + '\n' + gesture
        result = subprocess.run(['bash', '-uc', code], capture_output=True, text=True,
                                timeout=SHELL_TIMEOUT_SECONDS)
        released = (scratch / 'releases').read_text() == 'release\n'
        panel_drop = (scratch / 'panel.log').read_text().endswith('PANEL-DROP\n')
        catcher_drop = (scratch / 'catcher').read_text() == 'CATCHER-TEAROFF\n'
        detail = result.stdout + result.stderr
        if route == 'panel':
            check('panel hover alone permits normal release and PANEL-DROP',
                  result.returncode == 0 and released and panel_drop and not catcher_drop, detail)
        elif route == 'catcher':
            check('catcher hover alone permits normal release and catcher tear-off',
                  result.returncode == 0 and released and catcher_drop and not panel_drop, detail)
        else:
            check(route + ' receipt refuses before normal release',
                  result.returncode != 0 and not released and 'REFUSED' in result.stdout, detail)
    for receipt, succeeds, name in (
            ('PANEL-DROP\n', True, 'panel drop receipt counts as a panel drop'),
            ('PANEL-ENTER\n', False, 'panel hover alone never counts as a panel drop')):
        (scratch / 'panel.log').write_text(receipt)
        result = subprocess.run(['bash', '-c', setup + '\nlayerdrop_panel_hit "$log"'],
                                capture_output=True, text=True, timeout=SHELL_TIMEOUT_SECONDS)
        check(name, result.returncode == (0 if succeeds else 1), result.stdout + result.stderr)

print(f'{checks} layer receipt checks, {failures} failed')
raise SystemExit(bool(failures))
