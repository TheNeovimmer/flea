#!/usr/bin/env python3
# Names every colourless Rectangle that encloses a Flea.CheckBox under a ui root: one file:line per wrapper, exit 0 either way.
import os
import re
import sys

# An object-opening line, optionally behind a "prop:" prefix, with anything after the brace: "background: Rectangle { id: box".
OPEN = re.compile(r"^(\s*)(?:[\w. ]+:\s*)?([A-Z][\w.]*)\s*\{(.*)$")
# Sample input: "        Flea.CheckBox {" or "indicator: CheckBox {".
CHECKBOX = re.compile(r"^\s*(?:[\w. ]+:\s*)?(?:Flea\.)?CheckBox\s*\{")
# Sample input: "        color: Theme.surface" matches, "        border.color: x" does not.
DIRECT_COLOR = re.compile(r"^\s*(color|gradient)\s*:")


def indent_of(line):
    return len(line) - len(line.lstrip())


def has_direct_colour(lines, back, match):
    # True when the opener at `back` sets its own colour on the brace line or on a direct child row.
    indent = len(match.group(1))
    # Sample input: "Rectangle { color: x" sets a fill, "Rectangle { border.color: x" does not.
    if re.search(r"(?<![\w.])(color|gradient)\s*:", match.group(3)):
        return True
    rows = []
    child = None
    for ahead in range(back + 1, len(lines)):
        if not lines[ahead].strip():
            continue
        if indent_of(lines[ahead]) <= indent:
            break
        if child is None:
            child = indent_of(lines[ahead])
        if indent_of(lines[ahead]) == child:
            rows.append(lines[ahead])
    return any(DIRECT_COLOR.match(row) for row in rows)


def sweep(root):
    found = []
    for folder, names, files in os.walk(root):
        names.sort()
        for name in sorted(files):
            if not name.endswith(".qml"):
                continue
            path = os.path.join(folder, name)
            lines = open(path, encoding="utf-8").read().splitlines()
            for number, line in enumerate(lines):
                if not CHECKBOX.match(line):
                    continue
                indent = indent_of(line)
                for back in range(number - 1, -1, -1):
                    match = OPEN.match(lines[back])
                    if not match or len(match.group(1)) >= indent:
                        continue
                    indent = len(match.group(1))
                    if match.group(2) == "Rectangle" and not has_direct_colour(lines, back, match):
                        found.append("%s:%d" % (path, back + 1))
    return found


if __name__ == "__main__":
    for hit in sweep(sys.argv[1] if len(sys.argv) > 1 else "ui"):
        print(hit)
