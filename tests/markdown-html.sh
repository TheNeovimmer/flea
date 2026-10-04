#!/usr/bin/env bash
# Every Markdown fixture document, raw HTML and pathological nesting included, through the real preview: none may draw blank, and each raw HTML element draws as GitHub does.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "markdown-html.sh: qs is not installed, cannot render the preview"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-markdown-html-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-html.qml "$test_root/config/shell.qml" || exit 1
cp tests/markdown-html.js "$test_root/config/" || exit 1

# The head-to-head fixtures: fifteen documents, the logo and the 400-deep pathological one among them.
python3 tests/md-fixtures.py "$test_root/fx" > "$test_root/names" || exit 1
docs="$test_root/fx/docs"
# One-line probes the recipes are measured on, each beside its control.
printf 'Hx\n' > "$docs/16-sub-base.md"
printf 'H<sub>x</sub>\n' > "$docs/16-sub-low.md"
printf 'H<sup>x</sup>\n' > "$docs/16-sub-high.md"
printf 'A centred title\n' > "$docs/17-plain-title.md"
printf '<b>A centred title</b>\n' > "$docs/18-bold-title.md"
printf 'Press <kbd>Ctrl</kbd> now\n' > "$docs/19-key.md"
printf 'Press Ctrl now\n' > "$docs/19-nokey.md"
printf '<details>\n<summary>Open</summary>\n\nBody\n\n</details>\n' > "$docs/20-summary.md"
doc_list=$(cd "$docs" && ls -- *.md | paste -sd, -)

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MDHTML_DIR="$docs" FLEA_MDHTML_DOCS="$doc_list" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 600 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

printf '%s\n' "$output" | grep -aoE 'MARKDOWN_HTML .*'
# Sample input: MARKDOWN_HTML 31 checks, 0 failed
if ! printf '%s\n' "$output" | grep -qE 'MARKDOWN_HTML [1-9][0-9]* checks, 0 failed'; then
    printf 'FAIL markdown-html: a fixture drew blank or an element missed its recipe\n'
    printf '%s\n' "$output" | grep -aE 'ERROR|TypeError|ReferenceError' | head -10
    exit 1
fi
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
    mkdir -p "$FLEA_CI_SUITE_LOGS" || exit 1
    cp "$test_root/runtime"/markdown-html-*.png "$FLEA_CI_SUITE_LOGS/" 2>/dev/null
fi
echo "PASS markdown-html: every fixture draws, and each raw HTML element draws as its recipe"
