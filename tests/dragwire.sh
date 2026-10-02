#!/bin/bash
# Guards what an external application sees when Flea drags out. tests/drag.sh proves the
# gesture but needs the display and a real pointer, so it never runs in the headless battery.
# A plain file lift offers copy alone until the browser-upload work settles the offer: a browser
# uploader refuses a move offer. Ctrl offers copy alone, Shift move alone, Ctrl with Shift link
# alone, so a receiver that takes whatever is offered still takes the lift's verb. The shelf drag
# stays copy only. A tab drag offers Move alone with only the private tab type, so a foreign
# app refuses it and a tab can never move or copy the folder on disk.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

# Comments may name an action to explain it, so every check below reads code only.
code_of() { sed -e 's://.*::' "$1"; }

advertised=$(for f in ui/*.qml; do code_of "$f" | grep -H --label="$f" -n 'Drag\.supportedActions'; done)

# Exactly one file-drag advertiser of copy, the file lift, plus the tab drag's own Move.
copy_files=$(printf '%s' "$advertised" | grep 'CopyAction' | cut -d: -f1 | sort -u)
if [ "$(printf '%s' "$copy_files" | grep -c .)" -eq 1 ] && [ "$copy_files" = "ui/FileDrag.qml" ]; then
    ok "exactly one file-drag advertiser of copy: ui/FileDrag.qml"
else
    bad "expected the one copy advertiser to be ui/FileDrag.qml alone, found: $(printf '%s' "$copy_files" | tr '\n' ' ')"
fi
move_line=$(printf '%s' "$advertised" | grep '^ui/TabBar.qml' | cut -d: -f3-)
if printf '%s' "$move_line" | grep -q 'Drag\.supportedActions:[[:space:]]*Qt\.MoveAction[[:space:]]*$'; then
    ok "the tab drag advertises Move alone"
else
    bad "the tab drag must advertise Qt.MoveAction alone, got: $move_line"
fi

# Qt hands effectAllowed from this expression; combined Copy and Move violates the plain offer.
file_offer=$(code_of ui/FileDrag.qml | sed -n '/Drag\.supportedActions:/,/Qt.CopyAction/p')
if printf '%s' "$file_offer" | grep -q 'Qt\.CopyAction' && ! printf '%s' "$file_offer" | grep -q '|'; then
    ok "a plain file lift offers copy alone"
else
    bad "a plain file lift must offer Qt.CopyAction alone"
fi
if code_of ui/FileDrag.qml | grep -q 'dragCopy' && code_of ui/FileDrag.qml | grep -q 'dragShift' && code_of ui/FileDrag.qml | grep -q 'dragLink'; then
    ok "ctrl offers copy alone, shift move alone, ctrl with shift link alone"
else
    bad "the file offer must narrow on dragCopy, dragShift and dragLink"
fi
if code_of ui/FileDrag.qml | grep -q 'Qt\.LinkAction'; then
    ok "a link lift offers a link"
else
    bad "a link lift must offer Qt.LinkAction"
fi

# The Move-alone advertiser is the tab drag, and it carries no folder with it: Files
# moves a folder whenever Move is offered, so the private type rides alone. The file
# lift's own Shift move keeps its uri-list by the verb rule the checks above pin.
if grep -q 'text/uri-list' ui/TabBar.qml; then
    bad "the tab drag must not offer text/uri-list with Move"
else
    ok "no tab drag offers text/uri-list with Move"
fi
if code_of ui/js/Tabs.js | grep -q 'text/uri-list'; then
    bad "the tab payload must not offer text/uri-list"
else
    ok "the tab payload carries only the private tab type"
fi

if grep -q 'text/uri-list' ui/js/Drag.js; then
    ok "a leaving file drag still offers text/uri-list"
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

# Flea's own verb is the marker, not the DragEvent field. proposedAction may reach only the one
# helper in ui/js/Drag.js that ignores it for any Flea marker; QML call sites only pass it through
# to dropInto, dropVerb, feedbackFor, enterTarget or dropped. Anything else is the verb riding on it.
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
side=$(for f in ui/*.qml ui/js/*.js; do code_of "$f" | grep -H --label="$f" -n 'proposedAction'; done)
badside=""
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file=$(printf '%s' "$hit" | cut -d: -f1)
    text=$(printf '%s' "$hit" | cut -d: -f3-)
    case "$file" in
        ui/js/Drag.js) continue ;;
        ui/DropInto.qml|ui/RowDrag.qml|ui/FileDrag.qml)
            # Pass-through only: the offer setting and argument forwarding carry no decision.
            # A bitwise read or comparison here would decide the verb outside the helper.
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
# The helper must ignore the platform action for any Flea marker: no bitwise read of proposed
# outside foreignHeld. A verb decided elsewhere from proposedAction fails this before it ships.
bites=$(grep -n 'proposed &' ui/js/Drag.js)
start=$(grep -n '^function foreignHeld' ui/js/Drag.js | cut -d: -f1)
finish=$(awk -v s="$start" 'NR>s && /^function /{print NR; exit}' ui/js/Drag.js)
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

# The catcher must never steal focus and release the platform drag's held button.
if code_of ui/boot/tabtearoff.qml | grep -q 'WlrLayershell.keyboardFocus: WlrKeyboardFocus.None' \
    && ! code_of ui/boot/tabtearoff.qml | grep -Eq 'focus:|Keys\.|forceActiveFocus|WlrKeyboardFocus\.(OnDemand|Exclusive)'; then
    ok "tear-off catcher never requests keyboard focus"
else
    bad "tear-off catcher must use None without a focused Escape item"
fi
# A sibling source bypasses QQuickDropArea's ancestor rejection (QTBUG-64128).
if code_of ui/TabBar.qml | grep -q 'Drag.source: dragOrigin' \
    && code_of ui/TabBar.qml | grep -q 'Item { id: dragOrigin; width: 0; height: 0; visible: false }'; then
    ok "tab drag source is an invisible sibling of the strip DropArea"
else
    bad "tab drag source must not be the strip DropArea's ancestor"
fi

printf 'dragwire: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
