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

shot() {
    :
}

kill_flea() {
    :
}

key() {
    if [[ "$1" == -k && "$2" == Escape ]]; then
        escaped=true
    elif [[ "$1" != '?' ]]; then
        typed_query+="$1"
    fi
}

settle() {
    SECONDS=$((SECONDS + advance_s))
    printf '%s\n' "$SECONDS" > "$case_dir/elapsed"
}

ipc() {
    case "$1" in
        keymapSheetOpen) printf 'true\n' ;;
        keymapSheetRows) printf 'shift-delete delete permanently\n' ;;
        keymapQuery)
            if [[ "$escaped" == false ]]; then
                printf '%s\n' "$typed_query"
            elif [[ "$scenario" == persistent ]]; then
                printf 'perm\n'
            elif [[ "$scenario" == whitespace ]]; then
                printf ' \n'
            elif [[ "$scenario" == ipc-failure ]]; then
                return 1
            elif (( SECONDS < clear_after_s )); then
                printf 'perm\n'
            fi
            ;;
        *) return 2 ;;
    esac
}

# Sample input: omarchy-drive wait ipc -p /fixture/ui/boot flea keymapQuery "" --timeout 10
omarchy-drive() {
    local out
    out=$(ipc "$6") || return $?
    [[ "$out" == *"$7"* ]]
}

check_case() {
    local scenario="$1" expected_rc="$2" clear_after_s="$3" expected_elapsed="$4" diagnostic="$5"
    local case_dir="$scratch/$scenario" rc elapsed
    mkdir -p -- "$case_dir"
    printf '0\n' > "$case_dir/elapsed"
    (
        fixture_root="$case_dir"
        flea_ui="$case_dir/ui"
        escaped=false
        typed_query=""
        unset SECONDS
        SECONDS=0
        case_cap_sheet
    ) > "$case_dir/log" 2>&1
    rc=$?
    elapsed=$(cat "$case_dir/elapsed")
    checks=$((checks + 1))
    # Sample input: CAP_SHEET rest=ok query=perm
    if [[ "$rc" != "$expected_rc" || "$elapsed" != "$expected_elapsed" ]]; then
        printf 'FAIL %s: expected exit %s at %s s, got exit %s at %s s\n' \
            "$scenario" "$expected_rc" "$expected_elapsed" "$rc" "$elapsed"
        failed=$((failed + 1))
    elif [[ -n "$diagnostic" ]] && ! grep -Fq -- "$diagnostic" "$case_dir/log"; then
        printf 'FAIL %s: missing diagnostic %s\n' "$scenario" "$diagnostic"
        failed=$((failed + 1))
    elif [[ "$rc" == 0 ]] && ! grep -Fxq 'CAP_SHEET rest=ok query=perm' "$case_dir/log"; then
        printf 'FAIL %s: capture reported no success\n' "$scenario"
        failed=$((failed + 1))
    elif [[ "$rc" != 0 ]] && grep -q '^CAP_SHEET ' "$case_dir/log"; then
        printf 'FAIL %s: rejected query still reported capture success\n' "$scenario"
        failed=$((failed + 1))
    else
        printf 'ok %s\n' "$scenario"
    fi
}

check_case persistent 1 0 "$deadline_s" "last value 'perm'"
check_case whitespace 1 0 "$deadline_s" "last value ' '"
check_case delayed 0 "$delayed_clear_s" "$delayed_clear_s" ""
check_case immediate 0 0 0 ""
check_case late 1 "$((deadline_s + advance_s))" "$deadline_s" "last value 'perm'"
check_case ipc-failure 1 0 0 "keymapQuery failed after Escape"
printf 'ui-captures-sheet: %s checks, %s failed\n' "$checks" "$failed"
(( failed == 0 ))
