#!/usr/bin/env bash
# Every Markdown table case (wide, long cells, breaks, inline marks, ragged, nested, CJK, 500 rows) in Quick Look and the preview column: geometry judged, frames grabbed.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "markdown-tables.sh: qs is not installed, cannot render the preview"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-markdown-tables-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" "$test_root/docs" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-tables.js "$test_root/config/" || exit 1
cp tests/markdown-tables.qml "$test_root/config/shell.qml" || exit 1
cp tests/fixtures/markdown-tables/*.md "$test_root/docs/" || exit 1
. "$(dirname "$0")/markdown-tables-assets.sh" || exit 1

markdown_tables_assets_write "$test_root/docs" || exit 1

cases=wide,mid,extreme,sentence,path,br,inline,align,ragged,headonly,nested,cjk,adjacent,picturewide,rows500
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_TABLES_DIR="$test_root/docs" FLEA_TABLES_CASES="$cases" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 150 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

printf '%s\n' "$output" | grep -a 'MARKDOWN_TABLES' | grep -av ' GEO ' | sed 's/^.*MARKDOWN_TABLES //'
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
    mkdir -p "$FLEA_CI_SUITE_LOGS/tables" || exit 1
    cp "$test_root"/runtime/tables-*.png "$FLEA_CI_SUITE_LOGS/tables/" 2>/dev/null
    printf '%s\n' "$output" | grep -a ' GEO ' | sed 's/^.*MARKDOWN_TABLES GEO //' > "$FLEA_CI_SUITE_LOGS/tables/geometry.txt"
fi
if ! printf '%s\n' "$output" | grep -aq 'MARKDOWN_TABLES [0-9]* checks, 0 failed'; then
    printf 'FAIL markdown-tables: a table case failed or the run did not finish\n'
    exit 1
fi
printf 'markdown-tables: every case fits Quick Look; every case except wide and extreme fits the column\n'
