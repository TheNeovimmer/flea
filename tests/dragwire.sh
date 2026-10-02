#!/bin/bash
# Headless guard for what an external drop target sees: plain offers copy alone, Ctrl copy, Shift move, Ctrl with Shift link, shelf copy only.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

# Comments may name an action, so every check reads code only. Sample input, code_of('a // note') strips to 'a'.
code_of() { sed -e 's://.*::' "$1"; }

# Sample input, ui/FileDrag.qml:27: '    Drag.supportedActions: root.dragLink ? Qt.LinkAction : ...'
advertised=$(for f in ui/*.qml; do code_of "$f" | grep -H --label="$f" -n 'Drag\.supportedActions'; done)
count=$(printf '%s' "$advertised" | grep -c . )
if [ "$count" -eq 1 ]; then
    ok "exactly one view advertises a drag: $(printf '%s' "$advertised" | cut -d: -f1)"
else
    bad "expected exactly 1 Drag.supportedActions in ui/, found $count"
    printf '%s\n' "$advertised" | sed 's/^/     /'
fi

# Qt hands effectAllowed straight from this line: one ternary arm per lift, matched whole and end-anchored.
offer=$(printf '%s' "$advertised" | sed 's/^[^:]*:[0-9]*://')
if printf '%s' "$offer" | grep -q '^[[:space:]]*Drag\.supportedActions:[[:space:]]*root\.dragLink[[:space:]]*?[[:space:]]*Qt\.LinkAction[[:space:]]*:[[:space:]]*root\.dragCopy[[:space:]]*?[[:space:]]*Qt\.CopyAction[[:space:]]*:[[:space:]]*root\.dragShift[[:space:]]*?[[:space:]]*Qt\.MoveAction[[:space:]]*:[[:space:]]*Qt\.CopyAction[[:space:]]*$'; then
    ok "the offer narrows arm by arm: link alone, Ctrl copy alone, Shift move alone, plain copy alone"
else
    bad "the offer must read link/copy/shift/plain arm by arm, got: $offer"
fi

if grep -q 'text/uri-list' ui/js/Drag.js; then
    ok "a leaving drag still offers text/uri-list"
else
    bad "text/uri-list is gone from ui/js/Drag.js"
fi

# The shelf is a copy offer of its own and is not the leaving-file drag.
shelf=$(code_of shelf/ShelfCard.qml | grep -n 'Drag\.supportedActions')
if printf '%s' "$shelf" | grep -q 'Drag\.supportedActions:[[:space:]]*Qt\.CopyAction[[:space:]]*$'; then
    ok "the shelf drag stays a copy offer"
else
    bad "the shelf drag must stay Qt.CopyAction alone, got: $shelf"
fi

# Own verb rides the marker: proposedAction reaches only the Drag.js helper plus pass-through call sites (dropInto, dropVerb, feedbackFor, enterTarget, dropped).
if ! grep -q '^function foreignHeld' ui/js/Drag.js || ! grep -q '^function dropVerb' ui/js/Drag.js; then
    bad "ui/js/Drag.js must hold the single proposedAction helper (foreignHeld and dropVerb)"
else
    ok "the single proposedAction helper lives in ui/js/Drag.js"
fi
if ! grep -q 'dropVerb(marker, proposed' ui/js/Drag.js; then
    bad "dropInto must choose its verb through dropVerb"
else
    ok "dropInto chooses its verb through dropVerb"
fi
side=$(for f in ui/*.qml ui/js/*.js; do code_of "$f" | grep -H --label="$f" -n 'proposed'; done)
badside=""
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file=$(printf '%s' "$hit" | cut -d: -f1)
    text=$(printf '%s' "$hit" | cut -d: -f3-)
    case "$file" in
        ui/js/Drag.js) continue ;;
        ui/DropInto.qml|ui/RowDrag.qml|ui/FileDrag.qml)
            # Pass-through only (offer setting and argument forwarding); a bitwise read or comparison here would decide the verb outside the helper.
            case "$text" in
                *"&"*|*"=="*|*"!="*) ;;
                *) continue ;;
            esac
            ;;
    esac
    badside="${badside}${hit}
"
done <<< "$side"
if [ -z "$badside" ] && [ -n "$side" ]; then
    ok "proposedAction reaches only the helper and its pass-through call sites"
else
    bad "the internal verb is back on proposedAction outside the helper:"
    printf '%s\n' "${badside:-$side}" | sed 's/^/     /'
fi
# Helper ignores proposed for any Flea marker: no bitwise proposed read outside foreignHeld.
bites=$(grep -n 'proposed &' ui/js/Drag.js)
start=$(grep -n '^function foreignHeld' ui/js/Drag.js | cut -d: -f1)
finish=""
while IFS= read -r n; do
    if [ "$n" -gt "$start" ]; then
        finish=$n
        break
    fi
done <<< "$(grep -n '^function ' ui/js/Drag.js | cut -d: -f1)"
outside=""
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    n=$(printf '%s' "$hit" | cut -d: -f1)
    if [ -n "$start" ] && [ -n "$finish" ] && [ "$n" -ge "$start" ] && [ "$n" -lt "$finish" ]; then
        continue
    fi
    outside="${outside}${hit}
"
done <<< "$bites"
if [ -z "$outside" ] && [ -n "$bites" ]; then
    ok "only foreignHeld reads the proposedAction bits"
else
    bad "proposedAction bits are read outside foreignHeld:"
    printf '%s\n' "${outside:-none}" | sed 's/^/     /'
fi

printf 'dragwire: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
