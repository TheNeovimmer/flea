#!/usr/bin/env bash
# The real ui/PreviewMarkdown.qml over a fixture document, grabbed offscreen and judged
# on pixel facts: the chrome chip behind inline code, the table's rules without verticals,
# no Qt default link blue, and the quote bar's muted ink.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "markdown-render.sh: qs is not installed, cannot render the preview"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-markdown-render-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-render.qml "$test_root/config/shell.qml" || exit 1

cat > "$test_root/notes.md" <<'EOF'
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

![shot](https://cdn.example.com/shot.png)
EOF

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MARKDOWN_FIXTURE="$test_root/notes.md" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

# Sample input, the verdict line: "  INFO qml: MARKDOWN_RENDER PASS chip, rules, bar and links all read"
if [ "$(printf '%s\n' "$output" | grep -c 'MARKDOWN_RENDER PASS')" -ne 1 ] || printf '%s\n' "$output" | grep -q 'MARKDOWN_RENDER FAIL'; then
    printf 'FAIL the rendered preview missed a pixel fact\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_RENDER|ERROR|error' | head -20
    exit 1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the probe's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the render harness logged a warning\n'
    printf '%s\n' "$warnings" | head -10
    exit 1
fi
shot=$(ls "$test_root/runtime"/markdown-render-*.png 2>/dev/null | head -1)
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ] && [ -n "$shot" ]; then
    mkdir -p "$FLEA_CI_SUITE_LOGS" || exit 1
    cp "$shot" "$FLEA_CI_SUITE_LOGS/markdown-render.png" || exit 1
    printf 'shot %s\n' "$FLEA_CI_SUITE_LOGS/markdown-render.png"
elif [ -n "$shot" ]; then
    printf 'shot %s\n' "$shot"
fi
printf '%s\n' "$output" | grep -o 'MARKDOWN_RENDER PASS.*'
