# Shared by the native harnesses; Hyprland can warn about a missing window and exit zero.
# Sample input: hl.dsp.focus({ window = "address:0xabc" })
hypr_dispatch() {
    local answer window_field='window[[:space:]]*='
    if [[ "$1" =~ $window_field && "$1" != *address:* && "$1" != *class:* && "$1" != *title:* ]]; then
        printf 'Refused unscoped compositor dispatch: %s\n' "$1" >&2
        return 1
    fi
    if answer=$(hyprctl dispatch "$1" 2>&1) && [[ "$answer" == ok ]]; then
        return 0
    fi
    printf '%s\n' "$answer" >&2
    return 1
}
