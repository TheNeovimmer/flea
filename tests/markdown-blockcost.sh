#!/usr/bin/env bash
# Gate that a Markdown block builds only its own kind: a text block holds no table, list, quote, fence, figure or image parts, and every kind stays under its object count.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

# Object counts of one block, measured on the shipped delegate: a bare text block, and a two by two table with its measurers.
run_object_limit=12
heading_object_limit=12
table_object_limit=38
# Parts a table never draws.
table_foreign='Image|MarkdownFigure|TextMetrics|Glyph'

check_report() {
    local output=$1 kind line objects foreign limit
    for kind in run heading table list quote fence remote image; do
        # Sample input: MARKDOWN_BLOCKCOST kind=run objects=9 foreign=none parts={"MarkdownText":1}.
        line=$(printf '%s\n' "$output" | grep -aE "MARKDOWN_BLOCKCOST kind=$kind objects=" | head -1)
        if [ -z "$line" ]; then
            printf 'FAIL the harness never reported a %s block\n' "$kind"
            return 1
        fi
        objects=$(printf '%s\n' "$line" | grep -aoE 'objects=[0-9]+' | grep -aoE '[0-9]+')
        foreign=$(printf '%s\n' "$line" | grep -aoE 'foreign=[A-Za-z+]+' | cut -d= -f2)
        limit=""
        case $kind in
            run) limit=$run_object_limit ;;
            heading) limit=$heading_object_limit ;;
            table) limit=$table_object_limit ;;
        esac
        if [ -n "$limit" ] && [ "$objects" -gt "$limit" ]; then
            printf 'FAIL a %s block builds %s objects, the limit is %s\n' "$kind" "$objects" "$limit"
            return 1
        fi
        case $kind in
            run|heading)
                if [ "$foreign" != none ]; then
                    printf 'FAIL a %s block builds the parts of other kinds: %s\n' "$kind" "$foreign"
                    return 1
                fi ;;
            table)
                if printf '%s\n' "$foreign" | grep -qE "$table_foreign"; then
                    printf 'FAIL a table block builds the parts of other kinds: %s\n' "$foreign"
                    return 1
                fi ;;
        esac
    done
    printf 'PASS each block kind builds only its own parts within its object count\n'
}

# Controls: a report inside every limit passes, and a text block with table parts or a table over its count is refused.
control_limit=10
control_all=$(for kind in run heading table list quote fence remote image; do
    printf 'MARKDOWN_BLOCKCOST kind=%s objects=%s foreign=none parts={}\n' "$kind" "$control_limit"
done)
control_check() {
    ( run_object_limit=$control_limit heading_object_limit=$control_limit table_object_limit=$control_limit
      check_report "$1" ) >/dev/null
}
control_check "$control_all" || { echo "FAIL the gate refused a block inside its limits"; exit 1; }
if control_check "$(printf '%s\n' "$control_all" | sed 's/kind=run objects=10 foreign=none/kind=run objects=10 foreign=Column+Row/')"; then
    echo "FAIL the gate accepted a text block holding table parts"
    exit 1
fi
if control_check "$(printf '%s\n' "$control_all" | sed 's/kind=table objects=10/kind=table objects=11/')"; then
    echo "FAIL the gate accepted a table over its object count"
    exit 1
fi
printf 'ok the gate rejects foreign parts and a count over the limit\n'

if ! command -v qs >/dev/null; then
    echo "markdown-blockcost.sh: qs is not installed, cannot build the blocks"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-markdown-blockcost-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" "$test_root/docs" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Commons)" "$test_root/config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-blockcost.qml "$test_root/config/shell.qml" || exit 1

python3 - "$test_root/docs/kinds.png" <<'PY' || exit 1
import struct, sys, zlib
def chunk(tag, body):
    return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 8, 8, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress((b'\0' + b'\x40\x80\xc0' * 8) * 8)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
PY
# One block of every kind but the figure, whose picture arrives from a process and would change the count mid-census.
cat > "$test_root/docs/kinds.md" <<'MD'
# A heading

A paragraph with `code` and [a link](https://example.com/guide).

| Kind | Asks for |
| :--- | :--- |
| rows | the cursor |
| facts | the table |

1. First item
2. Second item

> A quoted line.

```js
var fenced = true;
```

![shot](https://cdn.example.com/shot.png)

![local](kinds.png)
MD

output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BLOCKCOST_LIST="$test_root/docs/kinds.md" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

printf '%s\n' "$output" | grep -aE 'MARKDOWN_BLOCKCOST (doc|kind)=' | sed 's/ parts=.*//'
if printf '%s\n' "$output" | grep -q 'MARKDOWN_BLOCKCOST FAIL'; then
    printf 'FAIL the harness refused its fixture\n'
    printf '%s\n' "$output" | grep -aE 'MARKDOWN_BLOCKCOST|ERROR' | head -10
    exit 1
fi
printf '%s\n' "$output" | grep -q 'MARKDOWN_BLOCKCOST DONE 1 documents' || { echo "FAIL the harness never finished"; exit 1; }
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF 'This plugin does not support setting window masks')
if [ -n "$warnings" ]; then
    printf 'FAIL the harness logged a warning\n'
    printf '%s\n' "$warnings" | head -10
    exit 1
fi
check_report "$output"
