#!/usr/bin/env bash
# Pins the Jump dropdown flush under the strip and the path field centred in it, by the margins the layout reads.
set -u
arg=${1:-}
if [ -n "$arg" ]; then tree=$(realpath -m -- "$arg") || exit 1; else tree=""; fi
cd "$(dirname "$0")/.." || exit 1
if [ -z "$tree" ]; then tree=$PWD; fi
# The scan finds a margin in a 12-line window after an anchor, which grep cannot express, so it is python.
python3 - "$tree" <<'PY'
# Each check reads the literal the layout reads, so a margin moved in QML moves the number here.
import re, sys

tree = sys.argv[1]

def fail(message):
    print('FAIL jump-gap ' + message)
    sys.exit(1)

def mult(expr):
    # Sample input: "Theme.spacing.hairline * 2" is 2, "Theme.spacing.hairline" is 1.
    m = re.fullmatch(r'Theme\.spacing\.hairline(?:\s*\*\s*(\d+))?', expr.strip())
    if not m:
        fail('a margin is no longer a hairline multiple: ' + expr.strip())
    return int(m.group(1)) if m.group(1) else 1

def inset(expr):
    # Sample input: "Theme.chromeFieldInset" is the symbol itself, anything else is not the shared inset.
    if expr.strip() != 'Theme.chromeFieldInset':
        fail('a field margin is not Theme.chromeFieldInset: ' + expr.strip())
    return expr.strip()

def after(lines, anchor, pattern):
    # Sample input: the "rename editor's own frame" comment, then "anchors.bottomMargin: ...".
    hits = []
    for n, line in enumerate(lines):
        if anchor in line:
            for later in lines[n:n + 12]:
                m = re.search(pattern, later)
                if m:
                    hits.append((n + 1, m.group(1)))
                    break
    return hits

def lines_of(rel):
    try:
        return open(tree + '/' + rel).read().split('\n')
    except OSError as e:
        fail('cannot read %s under %s: %s' % (rel, tree, e.strerror))

chrome = lines_of('ui/ChromeBar.qml')
jump = lines_of('ui/PathJump.qml')

slot = after(chrome, 'id: pathArea', r'anchors\.bottomMargin:\s*(.+?)\s*$')
slotTopHits = after(chrome, 'id: pathArea', r'anchors\.topMargin:\s*(.+?)\s*$')
frame_top = after(chrome, 'id: editFrame', r'anchors\.topMargin:\s*(.+?)\s*$')
frame_bot = after(chrome, 'id: editFrame', r'anchors\.bottomMargin:\s*(.+?)\s*$')
off = after(jump, 'y: root.parent', r'root\.parent\.height\s*\+\s*(.+?)\s*(?::\s*0\s*)?$')
for label, hits in (('path slot bottom', slot), ('field top', frame_top),
                    ('field bottom', frame_bot), ('dropdown offset', off)):
    if len(hits) != 1:
        fail('expected one %s margin, found %d' % (label, len(hits)))
if len(slotTopHits) > 1:
    fail('expected at most one path slot top margin, found %d' % len(slotTopHits))
slotTop = mult(slotTopHits[0][1]) if slotTopHits else 0

slotBot, dropOff = mult(slot[0][1]), mult(off[0][1])
# The field keeps the strip's control height (ButtonSystem040 A), so both margins are the one shared inset.
inset(frame_top[0][1]); inset(frame_bot[0][1])
if dropOff != slotBot:
    fail('the dropdown top misses the strip edge by %d hairline(s), so it covers the rule or floats' % (dropOff - slotBot))
if slotTop != 0:
    fail('the path slot has a top margin of %d hairline(s), so the equal field margins no longer centre it' % slotTop)
print('jump-gap: field margins are Theme.chromeFieldInset above and below, slot=%d off=%d, the dropdown hangs flush under the strip' % (slotBot, dropOff))
PY
