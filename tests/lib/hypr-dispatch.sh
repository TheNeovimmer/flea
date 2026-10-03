#!/usr/bin/env bash
# Only these typed functions build compositor commands; every window uses its validated address.
_hypr_refuse() {
    printf '%s: refused argument %q (%s)\n' "$1" "$2" "$3" >&2
    return 1
}

# Sample input: _hypr_arity hypr_window_resize 'ADDR W H' 0xabc 800 480.
_hypr_arity() {
    local helper="$1" signature="$2"
    local -a expected
    shift 2
    read -r -a expected <<< "$signature"
    [[ $# == ${#expected[@]} ]] || _hypr_refuse "$helper" "$*" "expected $signature"
}

# Sample input: hypr_window_focus 0xAbC, validated before adding the address: prefix.
_hypr_address() {
    [[ "$2" =~ ^0x[[:xdigit:]]+$ ]] || _hypr_refuse "$1" "$2" 'expected 0x followed by hex digits'
}

# Sample input: hypr_window_move -1920, signed coordinates allow monitors left of or above the origin.
_hypr_coordinate() {
    [[ "$2" =~ ^-?[0-9]+$ ]] || _hypr_refuse "$1" "$2" 'expected an integer coordinate'
}

# Sample input: hypr_window_resize 800, dimensions are nonnegative because they describe an extent.
_hypr_extent() {
    [[ "$2" =~ ^[0-9]+$ ]] || _hypr_refuse "$1" "$2" 'expected a nonnegative integer extent'
}

_hypr_reply_ok() {
    if [[ "$1" == 0 && "$2" == ok ]]; then
        return 0
    fi
    printf '%s\n' "$2" >&2
    return 1
}

hypr_window_focus() {
    _hypr_arity hypr_window_focus 'ADDR' "$@" || return 1
    _hypr_address hypr_window_focus "$1" || return 1
    local answer status=0
    answer=$(hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" 2>&1) || status=$?
    _hypr_reply_ok "$status" "$answer"
}

hypr_window_float() {
    _hypr_arity hypr_window_float 'ADDR on|off' "$@" || return 1
    _hypr_address hypr_window_float "$1" || return 1
    [[ "$2" == on || "$2" == off ]] || {
        _hypr_refuse hypr_window_float "$2" 'expected on or off'
        return 1
    }
    local answer status=0
    answer=$(hyprctl dispatch "hl.dsp.window.float({ action = \"$2\", window = \"address:$1\" })" 2>&1) || status=$?
    _hypr_reply_ok "$status" "$answer"
}

hypr_window_resize() {
    _hypr_arity hypr_window_resize 'ADDR W H' "$@" || return 1
    _hypr_address hypr_window_resize "$1" || return 1
    _hypr_extent hypr_window_resize "$2" || return 1
    _hypr_extent hypr_window_resize "$3" || return 1
    local answer status=0
    answer=$(hyprctl dispatch "hl.dsp.window.resize({ x = $2, y = $3, exact = true, window = \"address:$1\" })" 2>&1) || status=$?
    _hypr_reply_ok "$status" "$answer"
}

hypr_window_move() {
    _hypr_arity hypr_window_move 'ADDR X Y' "$@" || return 1
    _hypr_address hypr_window_move "$1" || return 1
    _hypr_coordinate hypr_window_move "$2" || return 1
    _hypr_coordinate hypr_window_move "$3" || return 1
    local answer status=0
    answer=$(hyprctl dispatch "hl.dsp.window.move({ x = $2, y = $3, window = \"address:$1\" })" 2>&1) || status=$?
    _hypr_reply_ok "$status" "$answer"
}

hypr_window_close() {
    _hypr_arity hypr_window_close 'ADDR' "$@" || return 1
    _hypr_address hypr_window_close "$1" || return 1
    local answer status=0
    answer=$(hyprctl dispatch "hl.dsp.window.close({ window = \"address:$1\" })" 2>&1) || status=$?
    _hypr_reply_ok "$status" "$answer"
}

hypr_cursor_move() {
    _hypr_arity hypr_cursor_move 'X Y' "$@" || return 1
    _hypr_coordinate hypr_cursor_move "$1" || return 1
    _hypr_coordinate hypr_cursor_move "$2" || return 1
    local answer status=0
    answer=$(hyprctl dispatch "hl.dsp.cursor.move({x = $1, y = $2})" 2>&1) || status=$?
    _hypr_reply_ok "$status" "$answer"
}

# Sample input: bash tests/lib/hypr-dispatch.sh window_resize 0xabc 800 480.
_hypr_program() {
    local operation="${1-}"
    [[ $# != 0 ]] || _hypr_refuse hypr-dispatch.sh "$operation" 'expected a typed operation' || return 1
    shift
    case "$operation" in
        window_focus) hypr_window_focus "$@" ;;
        window_float) hypr_window_float "$@" ;;
        window_resize) hypr_window_resize "$@" ;;
        window_move) hypr_window_move "$@" ;;
        window_close) hypr_window_close "$@" ;;
        cursor_move) hypr_cursor_move "$@" ;;
        *) _hypr_refuse hypr-dispatch.sh "$operation" 'unknown typed operation' ;;
    esac || return 1
    printf '%s\n' ok
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    _hypr_program "$@"
fi
