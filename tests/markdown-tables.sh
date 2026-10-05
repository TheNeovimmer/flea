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

# The inline image is a 12 by 12 dot, and the cost case is 500 rows of three cells.
python3 - "$test_root/docs" <<'PY' || exit 1
import struct, sys, zlib
root = sys.argv[1]
def chunk(tag, body):
    return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)
size = 12
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress((b'\0' + b'\x40\x80\xc0' * size) * size)) + chunk(b'IEND', b'')
open(root + '/dot.png', 'wb').write(png)
rows = ''.join('| row %d | a plain cell number %d | %d |\n' % (i, i, i * 7) for i in range(500))
open(root + '/rows500.md', 'w').write('# Rows\n\n| Name | Cell | Number |\n| --- | --- | ---: |\n' + rows)
PY

cases=wide,mid,extreme,sentence,path,br,inline,align,ragged,headonly,nested,cjk,adjacent,rows500
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
printf 'markdown-tables: every case fits in Quick Look and the column\n'
