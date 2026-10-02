#!/bin/bash
# Headless pins for the two-window UI case's pointer targeting and exit cleanup.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
repo=$PWD
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
source_file=${XW_HARNESS_SOURCE:-$repo/tests/ui.sh}
for helper in case_xwwatch xw_click_background xw_cleanup owned_trash_monitors; do
    eval "$(sed -n "/^$helper()/,/^}/p" "$source_file")" || exit 1
done
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
fixture_root="$tmp/fixtures"
flea_ui="$tmp/ui"
flea_bin="$tmp/flea"
run_root="$tmp/run"
settle_s=0
drain_wait_s=30
addr_a=0xaaa
addr_b=0xbbb
mkdir -p "$fixture_root" "$run_root"

# Sample clients: A at [100,200], B at [1000,200], both 880 by 620.
hyprctl() {
    if [[ "$*" == 'clients -j' ]]; then
        printf '[{"address":"%s","class":"com.thisisgm.flea","pid":111,"at":[100,200],"size":[880,620]},{"address":"%s","class":"com.thisisgm.flea","pid":222,"at":[1000,200],"size":[880,620]}]\n' "$addr_a" "$addr_b"
    elif [[ "$*" != "dispatch focuswindow address:$addr_a" ]]; then
        fail "unexpected compositor arguments: $*"
    fi
}
flea_window_class=com.thisisgm.flea
flea_process_owned() {
    [[ "$1" == 111 || "$1" == 222 ]]
}
omarchy-drive() {
    [[ "$*" == 'click 400 600 right' ]] || fail "pointer reached another window: $*"
    printf 'New Folder|New File|Paste\n' > "$tmp/menu"
    printf '%s\n' "$*" >> "$tmp/clicks"
}
xw_ipc() {
    local boot="$1" query="$2"
    shift 2
    case "$query" in
        listingBackgroundCentre)
            [[ "$boot" == "$fixture_root/xwwatch-ui/boot" ]] || fail "background point read from B"
            printf '300 %s\n' "${background_y:-400}"
            ;;
        fileRowHeight) printf '37\n' ;;
        rowCentre) printf '300 74\n' ;;
        total) printf '5\n' ;;
        contextMenuEntries) cat "$tmp/menu" ;;
        cursor)
            if [[ "$boot" == "$flea_ui/boot" ]]; then
                printf '3\n'
            else
                printf '%s\n' "${a_cursor:-0}"
            fi
            ;;
        selectionCount)
            if [[ -f "$tmp/deleted" ]]; then
                printf '2\n'
            else
                printf '3\n'
            fi
            ;;
        selectedIndices) printf '3,4\n' ;;
        rowAt)
            case "$1" in
                1) printf 'renamed-later.txt|file\n' ;;
                2) printf 'sel-one.txt|file\n' ;;
                3) printf 'sel-two.txt|file\n' ;;
                4) printf 'sel-three.txt|file\n' ;;
                *) printf 'untouched.txt|file\n' ;;
            esac
            ;;
        *) fail "unexpected IPC query: $query" ;;
    esac
}
ipc() {
    xw_ipc "$flea_ui/boot" "$@"
}
sandbox_scratch() {
    mkdir -p "$1"
}
xw_sweep_stale() {
    :
}
launch() {
    touch "$tmp/B.window" "$tmp/B.backend" "$tmp/B.monitor"
}
xw_second_window() {
    touch "$tmp/A.window" "$tmp/A.backend" "$tmp/A.monitor"
    printf '%s\n' "$addr_a"
}
flea_pid() {
    printf '222\n'
}
xw_addr_for_pid() {
    printf '%s\n' "$addr_b"
}
wait_listing() {
    :
}
seek_row_named() {
    :
}
key() {
    :
}
settle() {
    :
}
xw_settled() {
    :
}
xw_wait_total() {
    :
}
xw_wait_row() {
    :
}
xw_goto() {
    a_cursor=$3
}
xw_key() {
    if [[ "$*" == "$addr_a m" ]]; then
        printf 'Open|Open with|Cut|Copy\n' > "$tmp/menu"
    elif [[ "$*" == "$addr_a -k Delete" ]]; then
        touch "$tmp/deleted"
    fi
}
xw_menu_seek() {
    local entries
    entries=$(xw_ipc "$2" contextMenuEntries)
    [[ "$entries" == 'New Folder|New File'* ]] || fail "New File requires the background menu: $entries"
}
xw_wait_editor() {
    [[ "$mode" != failure ]] || fail 'injected editor failure'
}
xw_kill_second() {
    rm -f "$tmp/A.window"
}
kill_flea() {
    local window
    rm -f "$tmp/B.window"
    for window in A B; do
        if [[ ! -f "$tmp/$window.window" ]]; then
            rm -f "$tmp/$window.backend" "$tmp/$window.monitor"
        fi
    done
    [[ ! -f "$tmp/A.window" ]] || fail 'copied window survived teardown'
}

failures=0
for mode in success failure; do
    rm -f "$tmp/menu" "$tmp/deleted" "$tmp/clicks"
    result=0
    ( case_xwwatch ) > "$tmp/$mode.log" 2>&1 || result=$?
    expected=0
    [[ "$mode" != failure ]] || expected=1
    if [[ "$result" != "$expected" ]]; then
        printf 'FAIL xwwatch %s returned %s, expected %s\n' "$mode" "$result" "$expected"
        cat "$tmp/$mode.log"
        failures=$((failures + 1))
    fi
    if [[ "$mode" == failure ]] && ! grep -q 'injected editor failure' "$tmp/$mode.log"; then
        printf 'FAIL failure control did not reach the editor\n'
        failures=$((failures + 1))
    fi
    if compgen -G "$tmp/*.window" >/dev/null || compgen -G "$tmp/*.backend" >/dev/null || compgen -G "$tmp/*.monitor" >/dev/null; then
        printf 'FAIL xwwatch %s left an owned window, backend or monitor\n' "$mode"
        failures=$((failures + 1))
        rm -f "$tmp/"*.window "$tmp/"*.backend "$tmp/"*.monitor
    fi
done

if declare -F xw_click_background >/dev/null; then
    result=0
    (
        background_y=74
        xw_click_background "$addr_a" "$fixture_root/xwwatch-ui/boot"
    ) > "$tmp/row.log" 2>&1 || result=$?
    if [[ "$result" == 0 ]]; then
        printf 'FAIL a point on a listing row was accepted as empty space\n'
        failures=$((failures + 1))
    fi
fi

# Drive the copied-window stopper against a real child carrying this run's ownership marker.
eval "$(sed -n '/^xw_kill_second()/,/^}/p' "$source_file")" || exit 1
eval "$(sed -n '/^flea_process_owned()/,/^}/p' "$source_file")" || exit 1
flea_process_dir() {
    printf '/proc/%s\n' "$1"
}
dummy_lifetime_s=10
FLEA_TEST_RUN_ROOT="$run_root" bash -c 'exec -a "$1" sleep "$2"' _ "$fixture_root/xwwatch-ui" "$dummy_lifetime_s" &
test_pid=$!
pgrep() {
    printf '%s\n' "$test_pid"
}
result=0
( xw_kill_second "$fixture_root/xwwatch-ui" ) > "$tmp/stop.log" 2>&1 || result=$?
stopped=0
wait "$test_pid" 2>/dev/null || stopped=$?
terminated_status=143
if [[ "$result" != 0 || "$stopped" != "$terminated_status" ]]; then
    printf 'FAIL owned copied window was not terminated: helper=%s child=%s\n' "$result" "$stopped"
    failures=$((failures + 1))
fi

# A gio exits after ownership was proved but before the monitor's environ read.
mock_process="$tmp/process"
mkdir -p "$mock_process"
pgrep() {
    printf '333\n'
}
flea_process_dir() {
    printf '%s\n' "$mock_process"
}
flea_process_owned() {
    if [[ -d "$mock_process" ]]; then
        rmdir "$mock_process"
        return 0
    fi
    return 2
}
result=0
owned_trash_monitors > "$tmp/monitors.out" 2> "$tmp/monitors.err" || result=$?
if [[ "$result" != 0 || -s "$tmp/monitors.out" || -s "$tmp/monitors.err" ]]; then
    printf 'FAIL vanished Trash monitor emitted output or returned %s\n' "$result"
    cat "$tmp/monitors.err"
    failures=$((failures + 1))
fi
printf 'xw-harness: success cleanup, failure cleanup, A background target, row refusal, owned child stop, vanished monitor; %s failed\n' "$failures"
[[ "$failures" == 0 ]]
