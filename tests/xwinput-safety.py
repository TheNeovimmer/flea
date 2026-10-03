#!/usr/bin/env python3
# Run shipped cross-window input against a driver that refuses ambiguous class targets.
import os
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
UI = (ROOT / 'tests/ui.sh').read_text()
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


# Sample input: xwtab_key() {\n    omarchy-drive key --window "$addr" "$@"\n}.
def function(name, text=None):
    if text is None:
        text = UI
    # Sample input: hotkey() {\n    echo HOTKEY\n}\nkey() {\n    echo KEY\n}.
    match = re.search(r'^' + re.escape(name) + r'\(\) \{', text, re.M)
    if match is None:
        raise ValueError('missing shell helper: ' + name)
    start = match.start()
    return text[start:text.index('\n}', start) + 2]


fixture = 'hotkey() {\n    echo HOTKEY\n}\nkey() {\n    echo KEY\n}\n'
check('key extraction ignores an earlier hotkey declaration',
      function('key', fixture) == 'key() {\n    echo KEY\n}')


# Sample input: if key -k Escape; then :; fi, or omarchy-drive key -k Escape.
def ambiguous_input(body):
    prefix = r'(?:^|&&|\|\||;)\s*(?:(?:if|then)\s+)*'
    pattern = (prefix + r'(?:key|hotkey)\s|--window\s+flea\b|'
               + prefix + r'omarchy-drive\s+key\b(?![^;&|\n]*--window(?:\s|=))')
    # Sample input: key -k Escape >/dev/null, or omarchy-drive key --window flea /fixture.
    return re.search(pattern, body, re.M)


for prefix in ('xwdrag_focus "$bid" && ', 'xwdrag_focus "$bid" || ', 'if ', 'if true; then '):
    for helper in ('key', 'hotkey'):
        fixture = prefix + helper + ' -k Escape'
        check('ambiguity guard refuses ' + fixture, ambiguous_input(fixture) is not None)
check('ambiguity guard refuses driver key without window',
      ambiguous_input('omarchy-drive key -k Escape') is not None)
check('ambiguity guard accepts addressed driver key',
      ambiguous_input('omarchy-drive key --window "$addr" -k Escape') is None)


escape_start = UI.index('    # Escape mid-drag over A cancels')
escape_end = UI.index('    xwtab_wait_cancel', escape_start)
escape = 'escape_case() {\n' + UI[escape_start:escape_end] + '\n}\n'
navigation = function('xwdrag_navigate_second')
drag_case = function('case_xwdrag')
undo_start = drag_case.index('\n', drag_case.index("printf 'XWDRAG link ok")) + 1
undo_end = drag_case.index('    for i in ', undo_start)
undo = 'undo_case() {\n' + drag_case[undo_start:undo_end] + '\n}\n'

with tempfile.TemporaryDirectory() as temporary:
    scratch = pathlib.Path(temporary)
    calls = scratch / 'calls'
    driver = scratch / 'omarchy-drive'
    driver.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$DRIVER_CALLS"
refusal_status=1
if [[ "$2" != --window || "$3" == flea ]]; then
    printf "omarchy-drive: 'flea' matches 2 windows, narrow it\\n" >&2
    exit "$refusal_status"
fi
[[ "$3" == 0xa || "$3" == 0xb ]] || exit "$refusal_status"
[[ "$DRIVER_REFUSE_ADDRESS" != true ]] || exit "$refusal_status"
''')
    driver.chmod(0o700)
    environment = dict(os.environ, PATH=str(scratch) + os.pathsep + os.environ['PATH'],
                       DRIVER_CALLS=str(calls), DRIVER_REFUSE_ADDRESS='false')
    doubles = r'''
apid=101
bpid=202
bid=second
aid=first
want=/fixture
xwtab_button_down=false
fail() {
    printf 'FAIL %s\n' "$*"
    exit 1
}
assert_focus() { :; }
sleep() { :; }
xwtab_tab_point() { printf '348 121\n'; }
xwdrag_geometry() { printf '40 80 1000 720\n'; }
xwdrag_glide() { :; }
xwtab_mark_logs() { :; }
xwtab_wait_start() { :; }
ydotool() { :; }
hyprctl() {
    if [[ "$1" == clients ]]; then
        [[ "$xwtab_button_down" != true ]] || fail "address lookup while button held"
        printf '%s\n' '[{"pid":101,"address":"0xa"},{"pid":202,"address":"0xb"}]'
    elif [[ "$1" == dispatch ]]; then
        [[ "$xwtab_button_down" != true ]] || fail "focus changed while button held"
    fi
}
xwdrag_wait_focus() { :; }
xwdrag_focus() {
    [[ "$xwtab_button_down" != true ]] || fail "focus changed while button held"
}
xwdrag_qs() {
    case "$2" in
        pathBarOpen) printf 'true\n' ;;
        path) printf '%s\n' "$want" ;;
        listInFlight) printf 'false\n' ;;
    esac
}
'''
    helpers = function('key') + '\n' + function('xwtab_key')
    for name, body, invocation, expected in (
            ('held Escape', escape, 'escape_case', ['key --window 0xa -k Escape']),
            ('second-window navigation', navigation, 'xwdrag_navigate_second "$want"',
             ['key --window 0xb -M ctrl -k l -m ctrl', 'key --window 0xb /fixture',
              'key --window 0xb -k Return']),
            ('second-window undo', undo, 'undo_case', ['key --window 0xb -M ctrl -k z -m ctrl'])):
        for refuse_address in ('false', 'true'):
            calls.write_text('')
            environment['DRIVER_REFUSE_ADDRESS'] = refuse_address
            code = doubles + '\n' + helpers + '\n' + body + '\n' + invocation
            result = subprocess.run(['bash', '-uc', code], cwd=ROOT, capture_output=True,
                                    text=True, env=environment, timeout=SHELL_TIMEOUT_SECONDS)
            actual = calls.read_text().splitlines()
            detail = result.stdout + result.stderr + ' calls=' + repr(actual)
            if refuse_address == 'false':
                check(name + ' reaches the intended address with two windows',
                      result.returncode == 0 and actual == expected, detail)
            else:
                check(name + ' fails loudly on delivery refusal',
                      result.returncode != 0 and 'FAIL' in result.stdout and actual == expected[:1], detail)

    # Scan only multi-window bodies; opentab and tabdrag keep one window throughout.
    bodies = {'xwtab after second launch': function('case_xwtab').split('    xwdrag_launch_second', 1)[1],
              'xwdrag': function('case_xwdrag'), 'xwdrag navigation': navigation}
    for name, body in bodies.items():
        ambiguous = ambiguous_input(body)
        check(name + ' has no ambiguous input calls', ambiguous is None,
              ambiguous.group(0) if ambiguous else '')

print(f'{checks} cross-window input checks, {failures} failed')
raise SystemExit(bool(failures))
