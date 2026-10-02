#!/bin/bash
# Headless guard for what an external drop target sees, unlike tests/drag.sh which needs a display: plain offers copy alone since a browser uploader refuses a move, Ctrl copy, Shift move, Ctrl with Shift link, shelf copy only.
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

# Comparing the whole normalized offer pins every ternary arm and rejects a trailing token.
offer=$(code_of ui/FileDrag.qml | grep 'Drag\.supportedActions:' | sed 's/.*Drag\.supportedActions:[[:space:]]*//')
[ -n "$offer" ] || bad "no Drag.supportedActions line left in ui/FileDrag.qml to pin"
final=$(printf '%s\n' "$offer" | sed 's/.*://;s/[[:space:];]//g')
if [ "$final" = "Qt.CopyAction" ]; then
    ok "a plain lift offers copy alone"
else
    bad "a plain lift must end on Qt.CopyAction alone, got: $final"
fi
# Sample input: root.dragLink ? Qt.LinkAction : root.dragCopy ? Qt.CopyAction : root.dragShift ? Qt.MoveAction : Qt.CopyAction
offer_seq=$(printf '%s\n' "$offer" | tr -d '[:space:];' | sed -e 's/root\.//g' -e 's/?/ /g' -e 's/:/;/g')
# Link precedes copy because a link lift carries ctrl, so order decides the verb.
expected_seq='dragLink Qt.LinkAction;dragCopy Qt.CopyAction;dragShift Qt.MoveAction;Qt.CopyAction'
if [ "$offer_seq" = "$expected_seq" ]; then
    ok "the offer narrows arm by arm: link alone, Ctrl copy alone, Shift move alone, plain copy alone"
else
    bad "the offer must read $expected_seq, got: $offer_seq"
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
if [ -z "$start" ]; then
    bad "ui/js/Drag.js has no ^function foreignHeld line, so the single-helper range is unbounded"
fi
finish=""
while IFS= read -r n; do
    if [ "$n" -gt "${start:-0}" ]; then
        finish=$n
        break
    fi
done <<< "$(grep -n '^function ' ui/js/Drag.js | cut -d: -f1)"
if [ -z "$finish" ]; then
    finish=$(($(wc -l < ui/js/Drag.js) + 1))
fi
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
    bad "proposedAction bits are read outside foreignHeld lines $start-$finish:"
    printf '%s\n' "${outside:-no bitwise read left to place}" | sed 's/^/     /'
fi

# The shortened bound, and the fewest stub calls that show the wait kept polling.
short_wait_ns=300000000
min_poll_calls=2
# Sample input: "xwdrag_wait_row_gone() {", the ui.sh wait run with only its 10 s bound cut to short_wait_ns.
# The wait reads through xwdrag_count, so the guard comes along; the stub below answers both.
eval "$(sed -n '/^xwdrag_count()/,/^}/p;/^xwdrag_wait_row_gone()/,/^}/p' tests/ui.sh | sed "s/wait_ns=[0-9][0-9]*/wait_ns=$short_wait_ns/")"
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
