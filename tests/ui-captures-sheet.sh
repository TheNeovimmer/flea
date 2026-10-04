#!/usr/bin/env bash
# Runs the real capture case with controlled replies and a clock advanced only by settle.
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)" || exit 1
. "$repo/tests/ui-captures.sh"
. "$repo/tools/flea-sandbox-guard"
sandbox_root_ok
scratch=$(mktemp -d "$SANDBOX_ROOT/flea-capsheet.XXXXXX") || exit 1
: > "$scratch/$SANDBOX_MARKER"
trap 'sandbox_remove "$scratch"' EXIT

deadline_s=10
advance_s=1
delayed_clear_s=2
failed=0
checks=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

sandbox_scratch() {
    mkdir -p -- "$1"
}

seed_ui_state() {
    :
}

launch() {
    :
}

wait_listing() {
    :
}

# Sample input: cap-sheet-query-trash, appended to the case's shot list.
shot() {
    printf '%s\n' "$1" >> "$case_dir/shots"
}

kill_flea() {
    :
}

# The sheet opens on ?, Escape closes it (or the dialog standing over it), Enter on a row closes it and opens a dialog.
key() {
    if [[ "$1" == -k && "$2" == Escape ]]; then
        if [[ "$dialog_open" == true ]]; then
            [[ "$scenario" == dialog-stays ]] || dialog_open=false
        else
            escape_at=$SECONDS
        fi
    elif [[ "$1" == -k && "$2" == Return ]]; then
        sheet_open=false
        [[ "$scenario" == dialog-never ]] || dialog_open=true
    elif [[ "$1" == '?' ]]; then
        sheet_open=true
        escape_at=-1
        typed_query=""
    elif [[ "$1" != -k ]]; then
        typed_query+="$1"
    fi
}

settle() {
    SECONDS=$((SECONDS + advance_s))
    printf '%s\n' "$SECONDS" > "$case_dir/elapsed"
}

# Sample input: the perm query, answered with the action row and the live Permissions row; a bad scenario answers one wrong row.
sheet_rows() {
    case "$typed_query" in
        perm)
            case "$scenario" in
                dup-delete) printf 'shift-delete delete permanently\nshift-delete delete permanently\n Permissions\n' ;;
                perm-disabled) printf 'shift-delete delete permanently\n Permissions (disabled)\n' ;;
                rank-moved) printf ' Permissions\nshift-delete delete permanently\n' ;;
                *) printf 'shift-delete delete permanently\n Permissions\n' ;;
            esac ;;
        trash) printf ' Open Trash\nd trash\n' ;;
        comp)
            if [[ "$scenario" == comp-cap ]]; then printf 'z Compress\n Compress to .zip\n'
            elif [[ "$scenario" == comp-parent-only ]]; then printf ' Compress\n'
            else printf ' Compress\n Compress to .zip\n'; fi ;;
    esac
}

# What keymapSheetOpen answers after an Escape, by scenario; relative to the Escape, so each close is judged alone.
sheet_open_reply() {
    if [[ "$escape_at" -lt 0 ]]; then
        printf '%s\n' "$sheet_open"
    elif [[ "$scenario" == persistent ]]; then
        printf 'true\n'
    elif [[ "$scenario" == whitespace ]]; then
        printf ' \n'
    elif [[ "$scenario" == ipc-failure ]]; then
        return 1
    elif (( SECONDS - escape_at < clear_after_s )); then
        printf 'true\n'
    else
        printf 'false\n'
    fi
}

ipc() {
    case "$1" in
        keymapSheetOpen) sheet_open_reply ;;
        keymapSheetRows) sheet_rows ;;
        keymapQuery) printf '%s\n' "$typed_query" ;;
        permissionsState) printf '{"opened":%s,"busy":false}\n' "$dialog_open" ;;
        *) return 2 ;;
    esac
}

# Sample input: omarchy-drive wait ipc -p /fixture/ui/boot flea keymapQuery "" --timeout 10
omarchy-drive() {
    local out
    out=$(ipc "$6") || return $?
    [[ "$out" == *"$7"* ]]
}

# The shots a clean run takes, in order: the sheet at rest, then the query with a place, capless rows and a live row.
expected_shots='cap-sheet-rest
cap-sheet-query-trash
cap-sheet-query-comp
cap-sheet-query
cap-sheet-query-perm-file'

check_case() {
    local scenario="$1" expected_rc="$2" clear_after_s="$3" expected_elapsed="$4" diagnostic="$5"
    local case_dir="$scratch/$scenario" rc elapsed
    mkdir -p -- "$case_dir"
    printf '0\n' > "$case_dir/elapsed"
    (
        fixture_root="$case_dir"
        flea_ui="$case_dir/ui"
        sheet_open=false
        dialog_open=false
        escape_at=-1
        typed_query=""
        unset SECONDS
        SECONDS=0
        case_cap_sheet
    ) > "$case_dir/log" 2>&1
    rc=$?
    elapsed=$(cat "$case_dir/elapsed")
    checks=$((checks + 1))
    # Sample input: CAP_SHEET rest=ok queries=trash,comp,perm permissions=opened
    if [[ "$rc" != "$expected_rc" || "$elapsed" != "$expected_elapsed" ]]; then
        printf 'FAIL %s: expected exit %s at %s s, got exit %s at %s s\n' \
            "$scenario" "$expected_rc" "$expected_elapsed" "$rc" "$elapsed"
        failed=$((failed + 1))
    elif [[ -n "$diagnostic" ]] && ! grep -Fq -- "$diagnostic" "$case_dir/log"; then
        printf 'FAIL %s: missing diagnostic %s\n' "$scenario" "$diagnostic"
        failed=$((failed + 1))
    elif [[ "$rc" == 0 ]] && ! grep -Fxq 'CAP_SHEET rest=ok queries=trash,comp,perm permissions=opened' "$case_dir/log"; then
        printf 'FAIL %s: capture reported no success\n' "$scenario"
        failed=$((failed + 1))
    elif [[ "$rc" == 0 && "$(cat "$case_dir/shots")" != "$expected_shots" ]]; then
        printf 'FAIL %s: the shot list is %s\n' "$scenario" "$(tr '\n' ' ' < "$case_dir/shots")"
        failed=$((failed + 1))
    elif [[ "$rc" != 0 ]] && grep -q '^CAP_SHEET ' "$case_dir/log"; then
        printf 'FAIL %s: rejected sheet still reported capture success\n' "$scenario"
        failed=$((failed + 1))
    else
        printf 'ok %s\n' "$scenario"
    fi
}

# Each close is judged alone: a sheet that stays open (or answers blank) holds the deadline, a late close misses it.
check_case persistent 1 0 "$deadline_s" "last value 'true'"
check_case whitespace 1 0 "$deadline_s" "last value ' '"
check_case delayed 0 "$delayed_clear_s" "$((2 * delayed_clear_s))" ""
check_case immediate 0 0 0 ""
check_case late 1 "$((deadline_s + advance_s))" "$deadline_s" "last value 'true'"
check_case ipc-failure 1 0 0 "keymapSheetOpen failed"
# Each assertion the case adds has a control: the stub answers the bad value and the case must fail with that assertion's message.
check_case dup-delete 1 0 0 "delete permanently is listed more than once"
check_case perm-disabled 1 0 0 "Permissions reads unavailable"
check_case comp-cap 1 0 0 "the comp query lists a row with a cap"
check_case comp-parent-only 1 0 0 "the comp query lists no Compress to .zip leaf row"
check_case rank-moved 1 0 0 "the second perm row is not Permissions"
check_case dialog-never 1 0 "$deadline_s" "Enter on Permissions opened no dialog"
check_case dialog-stays 1 0 "$deadline_s" "Escape did not close the Permissions dialog"
printf 'ui-captures-sheet: %s checks, %s failed\n' "$checks" "$failed"
(( failed == 0 ))
