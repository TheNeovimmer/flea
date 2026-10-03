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
capmarkdown_wait_column_source() {
    local view="" source_poll_attempts=40 source_poll_seconds=0.1
    for _attempt in $(seq 1 "$source_poll_attempts"); do
        view="$(ipc columnMarkdownView)"
        [[ "$view" == "source" ]] && return 0
        sleep "$source_poll_seconds"
    done
    fail "capmarkdown: column Markdown never entered Source, last saw [$view]"
}
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

$$
x^2
$$

```math
\frac{a}{b}
```

```mermaid
not a diagram {{{
```

A paragraph with $x^2$ inline maths and $5 and $10 prices.

![shot](https://cdn.example.com/shot.png)
EOF
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
    key r >/dev/null
    settle
    shot "cap-markdown-source"
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
    capmarkdown_wait_column_source
    shot "cap-markdown-column-source"
    printf 'CAPMARKDOWN quicklook=ok source=ok column=ok column-source=ok\n'
    kill_flea
}
