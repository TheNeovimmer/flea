#!/bin/bash
# Guards what an external application sees when Flea drags a file out. tests/drag.sh proves the
# gesture but needs the display and a real pointer, so it never runs in the headless battery.
# A plain lift offers copy alone until the browser-upload work settles the offer: a browser
# uploader refuses a move offer. Ctrl offers copy alone, Shift move alone, Ctrl with Shift link
# alone, so a receiver that takes whatever is offered still takes the lift's verb. The shelf drag
# stays copy only.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

# Comments may name an action to explain it, so every check below reads code only.
code_of() { sed -e 's://.*::' "$1"; }

advertised=$(for f in ui/*.qml; do code_of "$f" | grep -H --label="$f" -n 'Drag\.supportedActions'; done)
count=$(printf '%s' "$advertised" | grep -c . )
if [ "$count" -eq 1 ]; then
    ok "exactly one view advertises a drag: $(printf '%s' "$advertised" | cut -d: -f1)"
else
    bad "expected exactly 1 Drag.supportedActions in ui/, found $count"
    printf '%s\n' "$advertised" | sed 's/^/     /'
fi

# Qt hands effectAllowed straight from this line. A plain lift names copy alone.
if printf '%s' "$advertised" | grep -q 'Qt\.CopyAction'; then
    ok "a leaving drag offers copy"
else
    bad "a leaving drag must offer Qt.CopyAction, got: $(printf '%s' "$advertised" | cut -d: -f3-)"
fi
if printf '%s' "$advertised" | grep -q 'Qt\.CopyAction | Qt\.MoveAction'; then
    bad "a plain lift must not offer both copy and move, got: $(printf '%s' "$advertised" | cut -d: -f3-)"
else
    ok "a plain lift offers copy alone"
fi
if printf '%s' "$advertised" | grep -q 'dragCopy' && printf '%s' "$advertised" | grep -q 'dragShift' && printf '%s' "$advertised" | grep -q 'dragLink'; then
    ok "ctrl offers copy alone, shift move alone, ctrl with shift link alone"
else
    bad "the offer must narrow on dragCopy, dragShift and dragLink, got: $(printf '%s' "$advertised" | cut -d: -f3-)"
fi
if printf '%s' "$advertised" | grep -q 'Qt\.LinkAction'; then
    ok "a link lift offers a link"
else
    bad "a link lift must offer Qt.LinkAction, got: $(printf '%s' "$advertised" | cut -d: -f3-)"
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

# The shortened bound, and the fewest stub calls that show the wait kept polling.
short_wait_ns=300000000
min_poll_calls=2
# Sample input: "xwdrag_wait_row_gone() {", the ui.sh wait run with only its 10 s bound cut to short_wait_ns.
eval "$(sed -n '/^xwdrag_wait_row_gone()/,/^}/p' tests/ui.sh | sed "s/wait_ns=[0-9][0-9]*/wait_ns=$short_wait_ns/")"
# A stub qs that fails every call, so the wait must keep polling to the bound.
xwdrag_qs() {
    printf 'call\n' >&3
    return 255
}
calls=$(
    {
        xwdrag_wait_row_gone stub-id "move.txt" >/dev/null 2>&1
        printf 'rc=%s\n' "$?"
    } 3>&1
)
wait_rc=$(printf '%s\n' "$calls" | sed -n 's/^rc=//p')
poll_calls=$(printf '%s\n' "$calls" | grep -c '^call$')
# A wait that saw no row and no total answers 1 only after polling for it.
if [ "$wait_rc" -eq 1 ] && [ "$poll_calls" -ge "$min_poll_calls" ]; then
    ok "a failing total call keeps waiting and answers 1 at the bound"
else
    bad "a failing total call must wait and answer 1, got rc=$wait_rc calls=$poll_calls"
fi

printf 'dragwire: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
