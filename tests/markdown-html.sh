#!/usr/bin/env bash
# Every Markdown fixture document, raw HTML and pathological nesting included, through the real preview: none may draw blank, and each raw HTML element draws as GitHub does.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
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
qslog_ui_copy "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-html.qml "$test_root/config/shell.qml" || exit 1
cp tests/markdown-html.js tests/markdown-html-pictures.js "$test_root/config/" || exit 1

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
# A local logo inside an HTML block the image rule does not take, and inside a wrapper whose closer is on a later line.
printf '<p align="center">\n<a href="https://example.com/x"><img src="img/logo.png" width="64" alt="logo"></a>\n</p>\n\nAfter\n' > "$docs/21-linked-logo.md"
printf '<table><tr><td><img src="img/logo.png" width="64" alt="logo"></td></tr></table>\n\nAfter\n' > "$docs/22-table-logo.md"
printf '<p align="center"><img src="img/logo.png" width="64" alt="logo">\n<br><b>Name</b>\n</p>\n\nAfter\n' > "$docs/23-open-wrapper.md"
printf '<p align=center><img src="img/logo.png" width="64" alt="logo">\n</p>\n\nAfter\n' > "$docs/24-empty-closer.md"
printf '<p align="center"><img src="img/logo.png" width="5000" alt="logo"></p>\n\nAfter\n' > "$docs/25-wide-logo.md"
# The flea-ci-visual README header: a heading and a paragraph on adjacent lines, and a line after a break.
cat > "$docs/26-readme-header.md" <<'MD'
<p align="center">
  <img src="img/logo.png" width="64" alt="logo">
</p>
<h1 align="center">Flea</h1>
<p align="center"><b>A file manager</b> for <i>Omarchy</i></p>

Press <kbd>Ctrl</kbd>+<kbd>C</kbd> to copy. Water is H<sub>2</sub>O and area is r<sup>2</sup>.<br>
A line after a break.

<details open>
<summary>More</summary>

Hidden body text.

</details>

<script>alert(1)</script>
<!-- a comment -->
<div align="right">Right aligned</div>
MD
printf 'Line one.<br>\nA line after a break.\n' > "$docs/27-break.md"
# A centred badge row of four linked pictures of different widths, and one row wider than the pane that wraps.
{
    printf '<p align="center">\n'
    for letter in a b c d; do
        printf '<a href="https://example.com/%s"><img src="img/badge-%s.png" alt="%s"></a>\n' "$letter" "$letter" "$letter"
    done
    printf '</p>\n\nAfter\n'
} > "$docs/28-badge-row.md"
{
    printf '<p align="center">\n'
    for n in 1 2 3 4 5 6; do
        printf '<a href="https://example.com/w%s"><img src="img/badge-w.png" alt="w%s"></a>\n' "$n" "$n"
    done
    printf '</p>\n\nAfter\n'
} > "$docs/29-badge-wrap.md"
# One picture size rule for a lone picture and for a row: a width past the natural size, no attribute on a wide picture, and both attributes.
printf '<p align="center"><img src="img/small.png" width="120" alt="s"></p>\n\nAfter\n' > "$docs/30-grow-single.md"
printf '<p align="center">\n<img src="img/small.png" width="120" alt="s">\n<img src="img/small.png" width="120" alt="s">\n</p>\n\nAfter\n' > "$docs/31-grow-row.md"
printf '<p align="center"><img src="img/big.png" alt="b"></p>\n\nAfter\n' > "$docs/32-natural-single.md"
printf '<p align="center">\n<img src="img/big.png" alt="b">\n<img src="img/badge-a.png" alt="a">\n</p>\n\nAfter\n' > "$docs/33-natural-row.md"
printf '<p align="center"><img src="img/logo.png" width="70" height="20" alt="l"></p>\n\nAfter\n' > "$docs/34-box-single.md"
printf '<p align="center">\n<img src="img/logo.png" width="70" height="20" alt="l">\n<img src="img/logo.png" width="70" height="20" alt="l">\n</p>\n\nAfter\n' > "$docs/35-box-row.md"
doc_list=$(cd "$docs" && ls -- *.md | paste -sd, -)

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_MDHTML_DIR="$docs" FLEA_MDHTML_DOCS="$doc_list" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 600 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

printf '%s\n' "$output" | qslog_nullptr markdown-html || exit 1
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
