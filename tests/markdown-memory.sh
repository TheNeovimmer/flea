#!/usr/bin/env bash
# The memory gate for rendered Markdown: with no Markdown file shown, no
# Markdown object is built and the Layouts module never loads. Static (a file
# path Loader, never an inline Component or a direct instantiation) plus a
# headless settle asserting both Loaders stayed null.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

# A file path, not an inline Component: nothing compiles at startup.
grep -q 'source: "MarkdownPane.qml"' ui/Preview.qml \
    || { echo "FAIL Quick Look builds its Markdown bar eagerly"; exit 1; }
grep -q 'source: "PreviewMarkdown.qml"' ui/PreviewColumn.qml \
    || { echo "FAIL the column builds its Markdown pane eagerly"; exit 1; }
if grep -nE '^[[:space:]]*(Flea\.)?(PreviewMarkdown|MarkdownPane)[[:space:]]*\{' ui/Preview.qml ui/PreviewColumn.qml; then
    echo "FAIL a Markdown pane is instantiated directly"
    exit 1
fi
# QtQuick's Grid, never GridLayout: the Layouts module must not load for this.
if grep -rn "^[[:space:]]*import QtQuick.Layouts" ui/PreviewMarkdown.qml ui/MarkdownPane.qml ui/Preview.qml ui/PreviewColumn.qml; then
    echo "FAIL the Markdown path imports QtQuick.Layouts"
    exit 1
fi
printf 'ok the Markdown panes load lazily and never import Layouts\n'

if ! command -v qs >/dev/null; then
    echo "markdown-memory.sh: qs is not installed, cannot count settled objects"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-markdown-memory-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-memory.qml "$test_root/config/shell.qml" || exit 1
echo "plain text" > "$test_root/note.txt" || exit 1

output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

if printf '%s\n' "$output" | grep -q 'MARKDOWN_MEMORY FAIL'; then
    printf 'FAIL the memory harness refused its window\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_MEMORY|ERROR' | head -10
    exit 1
fi
line=$(printf '%s\n' "$output" | grep -aE 'MARKDOWN_MEMORY lookMarkdown=' | head -1)
if [ -z "$line" ]; then
    printf 'FAIL the memory harness never settled (no live window ran)\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_MEMORY|ERROR|error' | head -20
    exit 1
fi
printf '%s\n' "$line" | grep -q 'lookMarkdown=null' || { echo "FAIL $line"; exit 1; }
printf '%s\n' "$line" | grep -q 'columnMarkdown=null' || { echo "FAIL $line"; exit 1; }
printf 'PASS %s\n' "$line"
