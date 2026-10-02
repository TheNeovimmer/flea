#!/usr/bin/env python3
# Keys handlers in PanelWindow files must belong to a focused Item.
import pathlib
import re
import sys

ITEM_TYPES = {'Item', 'Rectangle', 'FocusScope'}


# Sample input: 'PanelWindow { Item { focus: true; Keys.onPressed: function(event) {} } }'.
def keys_on_focused_item(text):
    tokens = re.findall(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_][\w.]*|[^\s]', text)
    tokens = [token for token in tokens if not token.startswith(('//', '/*'))]
    if 'PanelWindow' not in tokens: return True
    stack = []
    owners = []
    for i, token in enumerate(tokens):
        if token == '{':
            stack.append({'type': tokens[i - 1] if i else '', 'focused': False})
        elif token == '}':
            if stack: stack.pop()
        elif token == 'focus' and tokens[i + 1:i + 3] == [':', 'true'] and stack:
            stack[-1]['focused'] = True
        elif token.startswith('Keys.on'):
            owners.append(stack[-1] if stack else {})
    return all(owner.get('type') in ITEM_TYPES and owner.get('focused') for owner in owners)


def main(paths):
    bad = [path for path in paths if not keys_on_focused_item(pathlib.Path(path).read_text())]
    for path in bad: print('FAIL Keys must sit on a focused Item: ' + path)
    return bool(bad)


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
