# Sourced by ui.sh beside the other case files, but kept out of the default wanted
# list: it runs only by name. Opens a markdown fixture in Quick Look rendered, flips to
# Source and back with r, closes, then shoots the preview column with the file under the
# cursor. All fixtures and writes stay in its marked sandbox.
# Figures settle after the preview opens, so the shot waits for them.
capmarkdown_wait_figures() {
    local figs=""
    for _attempt in $(seq 1 60); do
        figs="$(ipc previewFigures)"
        if [[ -n "$figs" && "$figs" != *working* && "$figs" != *idle* && "$figs" != *deferred* ]]; then
            printf '%s\n' "$figs"
            return 0
        fi
        sleep 0.2
    done
    fail "capmarkdown: figures never settled, last saw [$figs]"
}
capmarkdown_wait_column_rendered() {
    local view="" rendered_poll_attempts=40 rendered_poll_seconds=0.1
    for _attempt in $(seq 1 "$rendered_poll_attempts"); do
        view="$(ipc columnMarkdownView)"
        [[ "$view" == "rendered" ]] && return 0
        sleep "$rendered_poll_seconds"
    done
    fail "capmarkdown: column Markdown never rendered after the Quick Look flip, last saw [$view]"
}
# Window pixels: the pointer goes to the document's centre (previewSurfaceRect's "x y w h", the body under the bar) or to the close button's own centre.
capmarkdown_pointer() {
    local where="$1" sx sy sw sh wx wy _ww _wh px py
    read -r wx wy _ww _wh < <(window_box) || fail "capmarkdown: native window coordinates unavailable"
    if [[ "$where" == close ]]; then
        read -r px py <<< "$(ipc previewCloseState | jq -r '.centre // empty' 2>/dev/null)"
        [[ -n "${py:-}" ]] || fail "capmarkdown: the close button never reported its centre"
    else
        read -r sx sy sw sh <<< "$(ipc previewSurfaceRect)"
        [[ -n "${sh:-}" ]] || fail "capmarkdown: the Quick Look surface never reported its rect"
        px=$((sx + sw / 2)); py=$((sy + sh / 2))
    fi
    px=$((wx + px)); py=$((wy + py))
    # Two moves so the first lands as the resting point, then a seat nudge there and back, since Hyprland's cursor move sends Qt no pointer frame.
    omarchy-drive move "$((px - capmarkdown_nudge_px * capmarkdown_approach_nudges))" "$py" >/dev/null || fail "capmarkdown: pointer approach to the $where failed"
    omarchy-drive move "$px" "$py" >/dev/null || fail "capmarkdown: pointer move to the $where failed"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x "$capmarkdown_nudge_px" -y 0 >/dev/null 2>&1 || fail "capmarkdown: pointer nudge failed"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x "-$capmarkdown_nudge_px" -y 0 >/dev/null 2>&1 || fail "capmarkdown: pointer nudge back failed"
    settle
    [[ "$where" != close ]] || capmarkdown_wait_close hovered true
}
# The close button's own pointer state, polled until it reads as wanted: a shot of a hover or a press is taken only once it holds.
capmarkdown_wait_close() {
    local field="$1" want="$2" state="" end
    end=$(( $(date +%s%3N) + capmarkdown_close_wait_s * 1000 ))
    while (( $(date +%s%3N) < end )); do
        state="$(ipc previewCloseState)"
        [[ "$(jq -r --arg field "$field" '.[$field]' <<< "$state" 2>/dev/null)" == "$want" ]] && return 0
        sleep "$capmarkdown_close_poll_s"
    done
    fail "capmarkdown: the close button never reported $field=$want, last [$state]"
}
# One wheel step run, its exit status kept, and the view proved to have moved: a shot taken after it is a scrolled shot.
capmarkdown_scroll() {
    local direction="$1" notches="$2" before after
    before="$(ipc previewScrollY)"
    omarchy-drive scroll "$direction" "$notches" >/dev/null || fail "capmarkdown: scroll $direction $notches failed"
    settle
    after="$(ipc previewScrollY)"
    [[ -n "$after" && "$after" != "$before" ]] || fail "capmarkdown: the wheel did not move the view, scrollY stayed [$before] after scroll $direction $notches"
}
# One px each way is enough for Hyprland to send Qt a pointer frame.
capmarkdown_nudge_px=1
# The approach starts this many nudges short of the target, so the second move is a real motion onto it.
capmarkdown_approach_nudges=6
# A hover or a press must read as wanted within this many seconds, read again after each pause.
capmarkdown_close_wait_s=5
capmarkdown_close_poll_s=0.05
# A notch is 288 px: three reach the figures region below the quote and tables, twelve more clamp at the tail with the picture and the placeholder.
capmarkdown_notches_mid=3
capmarkdown_notches_end=12
# Paragraphs of about 40 px rendered and two source lines each, so both views overflow a 2560 x 1440 card by more than the mid notches.
capmarkdown_notes=60
case_cap_markdown() {
    local dir="$fixture_root/capmarkdown" figs=""
    sandbox_scratch "$dir"
    mkdir -p "$dir/listing"
    cat > "$dir/listing/notes.md" <<'EOF'
# Rendered notes

## Second level

A paragraph with `loadFile()` inline code and [a guide](https://example.com/guide).

> A quoted line for the bar.

1. First item
2. Second item

- Alpha item
- Beta item

| Kind | Asks for | Cached |
| :--- | :--- | :--- |
| rows | the cursor | yes |
| facts | the table | yes |

```js
var fenced = true;
```

```mermaid
flowchart TD
    A --> B
```

```mermaid
sequenceDiagram
    A->>B: hi
```

$$x^2$$

```math
\frac{a}{b}
```

```mermaid
not a diagram {{{
```

## Notes
EOF
    for _note in $(seq 1 "$capmarkdown_notes"); do
        printf '\nNote %s of the fixture, plain text that only gives the document and its source some height.\n' "$_note" >> "$dir/listing/notes.md"
    done
    cat >> "$dir/listing/notes.md" <<'EOF'

A paragraph with $x^2$ inline maths and $5 and $10 prices.

![bench](./bench.png)

![shot](https://cdn.example.com/shot.png)
EOF
    # The board's 160 by 80 stand-in, written inside the fixture sandbox only.
    python3 - "$dir/listing/bench.png" <<'PY'
import struct, sys, zlib
def chunk(tag, body):
    return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 160, 80, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress((b'\0' + b'\x40\x80\xc0' * 160) * 80)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
PY
    launch "$dir/listing"
    # The fixture holds one file, so the listing is waited for at the count the fixture
    # creates rather than a literal carried from a larger fixture.
    wait_listing "$(find "$dir/listing" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
    goto_row "$(row_index_of notes.md)"
    key -k Space >/dev/null
    for _attempt in $(seq 1 40); do [[ "$(ipc previewOpen)" == "true" ]] && break; sleep 0.1; done
    [[ "$(ipc previewOpen)" == "true" ]] || fail "capmarkdown: Space did not open Quick Look on notes.md"
    settle
    figs="$(capmarkdown_wait_figures)"
    [[ "$(printf '%s' "$figs" | grep -o 'ready' | wc -l | tr -d ' ')" == "4" ]] || fail "capmarkdown: want 4 ready figures, saw [$figs]"
    [[ "$(printf '%s' "$figs" | grep -o 'failed' | wc -l | tr -d ' ')" == "1" ]] || fail "capmarkdown: want 1 failed figure, saw [$figs]"
    shot "cap-markdown-rendered"
    # Rendered scrolled: the wheel shows the scroll bar on use, so each shot holds it.
    capmarkdown_pointer document
    capmarkdown_scroll down "$capmarkdown_notches_mid"
    shot "cap-markdown-rendered-scrolled"
    capmarkdown_scroll down "$capmarkdown_notches_end"
    shot "cap-markdown-rendered-end"
    capmarkdown_scroll up "$((capmarkdown_notches_mid + capmarkdown_notches_end))"
    # The close button in each state the bar can show: hover, keyboard focus after Tab, then pressed and released off the button.
    capmarkdown_pointer close
    shot "cap-markdown-close-hover"
    capmarkdown_pointer document
    key -k Tab >/dev/null
    settle
    shot "cap-markdown-close-focus"
    capmarkdown_pointer close
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool click 0x40 >/dev/null 2>&1 || fail "capmarkdown: pointer press on the close button failed"
    settle
    capmarkdown_wait_close pressed true
    shot "cap-markdown-close-press"
    capmarkdown_pointer document
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool click 0x80 >/dev/null 2>&1 || fail "capmarkdown: pointer release failed"
    settle
    [[ "$(ipc previewOpen)" == "true" ]] || fail "capmarkdown: a press released off the close button closed Quick Look"
    # The control: a press and release both on the close button closes, then Space opens the document again for the Source steps.
    capmarkdown_pointer close
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool click 0xC0 >/dev/null 2>&1 || fail "capmarkdown: pointer click on the close button failed"
    settle
    [[ "$(ipc previewOpen)" == "false" ]] || fail "capmarkdown: a press and release on the close button did not close Quick Look"
    key -k Space >/dev/null
    for _attempt in $(seq 1 40); do [[ "$(ipc previewOpen)" == "true" ]] && break; sleep 0.1; done
    [[ "$(ipc previewOpen)" == "true" ]] || fail "capmarkdown: Space did not reopen Quick Look after the close button closed it"
    settle
    capmarkdown_wait_figures >/dev/null
    key r >/dev/null
    settle
    shot "cap-markdown-source"
    capmarkdown_scroll down "$capmarkdown_notches_mid"
    shot "cap-markdown-source-scrolled"
    key r >/dev/null
    settle
    capmarkdown_wait_figures >/dev/null
    shot "cap-markdown-rendered-again"
    key -k Escape >/dev/null
    settle
    [[ "$(ipc previewOpen)" == "false" ]] || fail "capmarkdown: Escape did not close Quick Look"
    switch_view columns
    goto_row "$(row_index_of notes.md)"
    settle
    shot "cap-markdown-column"
    key -k Space >/dev/null
    for _attempt in $(seq 1 40); do [[ "$(ipc previewOpen)" == "true" ]] && break; sleep 0.1; done
    [[ "$(ipc previewOpen)" == "true" ]] || fail "capmarkdown: Space did not reopen Quick Look from columns"
    key r >/dev/null
    settle
    key -k Escape >/dev/null
    settle
    [[ "$(ipc previewOpen)" == "false" ]] || fail "capmarkdown: Escape did not close Source Quick Look"
    capmarkdown_wait_column_rendered
    shot "cap-markdown-column-after-flip"
    printf 'CAPMARKDOWN quicklook=ok source=ok column=ok column-after-flip=ok\n'
    kill_flea
}
