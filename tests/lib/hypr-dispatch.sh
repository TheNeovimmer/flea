# Shared by the native harnesses; Hyprland can warn about a missing window and exit zero.
# Sample input: hl[.]dsp[.](focus[(]|window[.])\n(^|[,{])\s*window\s*=\s*"(address|class|title):\n
{
    IFS= read -r HYPR_DISPATCH_WINDOW_CALL
    IFS= read -r HYPR_DISPATCH_WINDOW_SELECTOR
} < "$(dirname "${BASH_SOURCE[0]}")/hypr-dispatch.regex" || return 1

# Sample input: hl.dsp.focus({ window = "address:0xabc" })
hypr_dispatch() {
    local answer
    if [[ "$1" =~ $HYPR_DISPATCH_WINDOW_CALL && ! "$1" =~ $HYPR_DISPATCH_WINDOW_SELECTOR ]]; then
        printf 'Refused unscoped compositor dispatch: %s\n' "$1" >&2
        return 1
    fi
    if answer=$(hyprctl dispatch "$1" 2>&1) && [[ "$answer" == ok ]]; then
        return 0
    fi
    printf '%s\n' "$answer" >&2
    return 1
}
