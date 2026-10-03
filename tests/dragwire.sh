#!/bin/bash
# Guards what an external application sees when Flea drags out. tests/drag.sh proves the
# gesture but needs the display and a real pointer, so it never runs in the headless battery.
# A plain file lift offers copy alone until the browser-upload work settles the offer: a browser
# uploader refuses a move offer. Ctrl offers copy alone, Shift move alone, Ctrl with Shift link
# alone, so a receiver that takes whatever is offered still takes the lift's verb. The shelf drag
# stays copy only. A tab drag offers Move alone with only the private tab type, so a foreign app refuses it.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

# Comments may name an action, so every check reads code only. Sample input: Drag.supportedActions: Qt.MoveAction // explanatory comment, which is ignored.
code_of() { sed -e 's://.*::' "$1"; }

# Sample input, ui/FileDrag.qml:27: '    Drag.supportedActions: root.dragLink ? Qt.LinkAction : ...'
advertised=$(while IFS= read -r f; do
    code_of "$f" | grep -H --label="$f" -n 'Drag\.supportedActions'
done < <(find ui -type f -name '*.qml'))

advertiser_files=$(printf '%s\n' "$advertised" | cut -d: -f1 | sort -u)
expected_advertisers=$(printf '%s\n' ui/FileDrag.qml ui/TabBar.qml | sort -u)
if [[ "$advertiser_files" == "$expected_advertisers" ]]; then
    ok "only ui/FileDrag.qml and ui/TabBar.qml advertise drag actions: one view per drag kind"
else
    bad "unexpected Drag.supportedActions files: $advertiser_files"
fi

# Each advertiser holds exactly one line, so a second offer in either file cannot hide behind the set check above.
file_lines=$(printf '%s\n' "$advertised" | grep -c '^ui/FileDrag.qml:')
tab_lines=$(printf '%s\n' "$advertised" | grep -c '^ui/TabBar.qml:')
if [ "$file_lines" -eq 1 ] && [ "$tab_lines" -eq 1 ]; then
    ok "exactly one Drag.supportedActions line in each of ui/FileDrag.qml and ui/TabBar.qml"
else
    bad "expected one Drag.supportedActions line in each advertiser, found FileDrag=$file_lines TabBar=$tab_lines"
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

# FileDrag and Drag.js offer uri-list; DropInto and RowDrag consume it, with no other ui users.
uri_files=$(while IFS= read -r f; do
    code_of "$f" | grep -H --label="$f" 'text/uri-list'
done < <(find ui -type f \( -name '*.qml' -o -name '*.js' \)) | cut -d: -f1 | sort -u)
expected_uri_files=$(printf '%s\n' ui/DropInto.qml ui/FileDrag.qml ui/RowDrag.qml ui/js/Drag.js | sort -u)
if [[ "$uri_files" == "$expected_uri_files" ]]; then
    ok "uri-list is confined to the file payload producers and their two receivers"
else
    bad "unexpected text/uri-list files: $uri_files"
fi

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
scratch=$(mktemp -d) || exit 1
trap 'rm -rf "$scratch"' EXIT
# Load the exact component outside ui's qmldir, which eagerly imports unrelated Quickshell singletons.
cp ui/FileDrag.qml "$scratch/FileDrag.qml" || exit 1
ln -s "$PWD/ui/js" "$scratch/js" || exit 1
offer_timeout_seconds=15
file_offer=$(env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout "$offer_timeout_seconds" qml6 tests/dragwire-offer.qml -- "$scratch/FileDrag.qml" 2>&1)
offer_status=$?
if [[ "$offer_status" == 0 ]] && grep -q 'file offers: 5 checks, 0 failed' <<< "$file_offer"; then
    ok "file lift offers copy for plain, ctrl and ctrl plus shift without link; shift offers move and link takes priority"
else
    bad "file lift offers failed (status=$offer_status): $file_offer"
fi

# Exercise the shipped floor bindings and handler while a listing is held and after it settles.
floor_probe_seconds=15
floor_output=$(env QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout "$floor_probe_seconds" qml6 tests/dragwire-floor.qml 2>&1)
floor_status=$?
if [[ "$floor_status" == 0 ]] && grep -q 'floor drops: 21 checks, 0 failed' <<< "$floor_output"; then
    ok "list, grid and columns floors refuse held listings and target the shown directory after settlement"
else
    bad "floor drops failed (status=$floor_status): $floor_output"
fi

# The Move-alone advertiser is the tab drag: it carries the private type alone, since Files moves a folder whenever Move is offered.
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
